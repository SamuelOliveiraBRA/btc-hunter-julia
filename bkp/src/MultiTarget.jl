module MultiTarget

using ..BloomFilter

export TargetSet, build_target_set, check_hit, address_from_hash, target_count

"""
    TargetSet
Conjunto de endereços alvo. Combina BloomFilter para escala absurda
(rejeição ultra-rápida de bilhões de endereços) com HashSet para colisão final garantida.
"""
struct TargetSet
    hashes   :: Set{Vector{UInt8}}
    addr_map :: Dict{Vector{UInt8}, String}
    bloom    :: FastBloom
    use_bloom:: Bool
end

"""
    build_target_set(addresses, decode_fn)
Constrói um TargetSet a partir de uma lista de endereços Bitcoin.
`decode_fn` deve converter endereço String → Vector{UInt8} (hash160).
"""
function build_target_set(addresses::Vector{String}, decode_fn::Function)::TargetSet
    hashes   = Set{Vector{UInt8}}()
    addr_map = Dict{Vector{UInt8}, String}()

    for addr in addresses
        isempty(strip(addr)) && continue
        try
            h = decode_fn(addr)
            push!(hashes, h)
            addr_map[h] = addr
        catch e
            @warn "Endereço inválido ignorado: '$addr' — $e"
        end
    end

    # Se a DB for maior que 10.000 hashes, ativamos o Bloom Filter
    # para não sobrecarregar lookups na Tabela Hash em memória viva
    use_bloom = length(hashes) > 10_000
    bf = BloomFilter.load_massive_targets(collect(hashes))

    return TargetSet(hashes, addr_map, bf, use_bloom)
end

"""
    check_hit(ts, h160)
Verifica se um Hash160 está entre os alvos. O(1).
"""
@inline function check_hit(ts::TargetSet, h160::Vector{UInt8})::Bool
    if ts.use_bloom
        BloomFilter.check_hash(ts.bloom, h160) || return false
    end
    return h160 in ts.hashes
end

"""
    address_from_hash(ts, h160)
Retorna o endereço Bitcoin correspondente ao hash160, ou string vazia.
"""
function address_from_hash(ts::TargetSet, h160::Vector{UInt8})::String
    return get(ts.addr_map, h160, "")
end

"""
    target_count(ts)
Número de endereços alvo carregados.
"""
target_count(ts::TargetSet)::Int = length(ts.hashes)

end # module MultiTarget
