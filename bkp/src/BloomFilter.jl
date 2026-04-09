module BloomFilter

# ═══════════════════════════════════════════════════════════════════
# BloomFilter.jl — Estrutura de dados probabilística super rápida
#
# Criado para lidar com bases gigantes (milhões de Hash160)
# usando O(1) de tempo de processamento e baixíssimo footprint
# de memória comparado com um Set{} nativo do Julia.
# ═══════════════════════════════════════════════════════════════════

export FastBloom, add_hash!, check_hash, load_massive_targets

"""
    FastBloom
Filtro de Bloom otimizado para arrays de 20 bytes (Hash160).
"""
struct FastBloom
    bits::BitVector
    m::Int # Tamanho em bits
    k::Int # Número de funções de hash
end

function FastBloom(expected_items::Int, false_positive_rate::Float64 = 0.0001)
    # Cálculo ideal do tamanho do bit-array e quantidade de saltos
    m = ceil(Int, - (expected_items * log(false_positive_rate)) / (log(2)^2))
    k = ceil(Int, (m / expected_items) * log(2))
    bits = falses(m)
    return FastBloom(bits, m, k)
end

"""
    _get_indices(bf, data)
Gera k índices independentes usando MurmurHash3 e seeds derivadas.
"""
function _get_indices(bf::FastBloom, data::Vector{UInt8})::Vector{Int}
    inds = Vector{Int}(undef, bf.k)
    # Hashing principal (Julia nativo usa C-level MurmurHash/SipHash)
    h1 = hash(data, 0x1234567890abcdef)
    h2 = hash(data, 0xfedcba0987654321)
    
    # Derivação de k hashes com Double Hashing: h_i = (h1 + i * h2) % m
    for i in 1:bf.k
        mix = h1 + (i * h2)
        # mod1 garante 1-based indexing para Julia
        inds[i] = mod1(abs(mix), bf.m)
    end
    return inds
end

"""
    add_hash!(bf, hash160_bytes)
Adiciona um array de 20 bytes (Hash160) no Bloom Filter.
"""
function add_hash!(bf::FastBloom, data::Vector{UInt8})
    inds = _get_indices(bf, data)
    for idx in inds
        bf.bits[idx] = true
    end
end

"""
    check_hash(bf, hash160_bytes) -> Bool
Verifica rapidamente se um Hash160 (pode) estar no set.
Pode ter falsos positivos locais (o check final de Set é necessário num hit real).
"""
function check_hash(bf::FastBloom, data::Vector{UInt8})::Bool
    inds = _get_indices(bf, data)
    for idx in inds
        if !bf.bits[idx]
            return false
        end
    end
    return true
end

"""
    load_massive_targets(hash_list)
Cria um Bloom Filter e popula-o para uma lista grande de hashes (Vector de 20 bytes).
"""
function load_massive_targets(hash_list::Vector{Vector{UInt8}})::FastBloom
    n = length(hash_list)
    # Tratativa para arrays pequenos
    expected = n < 10_000 ? 10_000 : n
    bf = FastBloom(expected)
    for h in hash_list
        add_hash!(bf, h)
    end
    return bf
end

end # module BloomFilter
