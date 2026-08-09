module Bip39Solver

using SHA
using Secp256k1
using Base.Threads: @threads

export load_wordlist, index_map, checksum_valid, mnemonic_to_seed,
       derive_private_key_bip32, derive_address, brute_unknown_positions

# ═══════════════════════════════════════════════════════════
#  BIP39 SOLVER · Solucionador de puzzles de frase mnemônica
#  Reutiliza a infraestrutura do BTC Hunter Julia
#         (Base58 / SHA / ripemd160 via libcrypto / Secp256k1)
#  Derivação: BIP39 seed → BIP32 m/44'/0'/0'/0/0 (P2PKH comprimido)
# ═══════════════════════════════════════════════════════════

const N_CURVE = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"; base=16)

# ── Wordlist ─────────────────────────────────────────────────

"""
    load_wordlist(path)
Carrega a wordlist BIP39 (uma palavra por linha, ordem oficial).
"""
function load_wordlist(path::String)::Vector{String}
    return readlines(path)
end

"""
    index_map(words)::Dict{String,Int}
Mapa palavra -> índice (0-based, como exige o BIP39).
"""
function index_map(words::Vector{String})::Dict{String,Int}
    d = Dict{String,Int}()
    for (i, w) in enumerate(words)
        d[w] = i - 1
    end
    return d
end

# ── PBKDF2-HMAC-SHA512 ───────────────────────────────────────

function pbkdf2_hmac_sha512(pass::Vector{UInt8}, salt::Vector{UInt8}, iters::Int, dklen::Int)::Vector{UInt8}
    hlen = 64
    nblocks = cld(dklen, hlen)
    out = Vector{UInt8}()
    for blk in 1:nblocks
        u = vcat(salt, [UInt8(blk >> 24), UInt8(blk >> 16), UInt8(blk >> 8), UInt8(blk & 0xFF)])
        u = hmac_sha512(pass, u)
        t = copy(u)
        for _ in 2:iters
            u = hmac_sha512(pass, u)
            for i in 1:hlen
                t[i] = t[i] ⊻ u[i]
            end
        end
        append!(out, t)
    end
    return out[1:dklen]
end

"""
    mnemonic_to_seed(mnemonic::String)
Seed de 64 bytes a partir da frase mnemônica (BIP39, sem passphrase).
"""
function mnemonic_to_seed(mnemonic::String)::Vector{UInt8}
    return pbkdf2_hmac_sha512(Vector{UInt8}(mnemonic), Vector{UInt8}("mnemonic"), 2048, 64)
end

# ── Checksum BIP39 ──────────────────────────────────────────

"""
    checksum_valid(words, idxmap)::Bool
Valida o checksum de 12 palavras (4 bits sobre 128 bits de entropia).
"""
function checksum_valid(words::Vector{String}, idxmap::Dict{String,Int})::Bool
    io = IOBuffer()
    for w in words
        print(io, string(idxmap[w], base=2, pad=11))
    end
    bits = String(take!(io))
    ent = parse(UInt128, bits[1:end-4]; base=2)
    cs  = bits[end-3:end]
    entbytes = zeros(UInt8, 16)
    for i in 16:-1:1
        entbytes[i] = UInt8(ent & 0xFF)
        ent >>= 8
    end
    h = SHA.sha256(entbytes)
    return string(h[1], base=2, pad=8)[1:4] == cs
end

# ── BIP32 (m/44'/0'/0'/0/0) ────────────────────────────────

function _big2bytes32(n::BigInt)::Vector{UInt8}
    out = zeros(UInt8, 32)
    for i in 32:-1:1
        out[i] = UInt8(n & 0xFF)
        n >>= 8
    end
    return out
end

"""
    derive_private_key_bip32(words, idxmap)::BigInt
Chave privada na derivação m/44'/0'/0'/0/0 a partir da seed BIP39.
"""
function derive_private_key_bip32(words::Vector{String}, idxmap::Dict{String,Int})::BigInt
    seed = mnemonic_to_seed(join(words, " "))
    I = hmac_sha512(Vector{UInt8}("Bitcoin seed"), seed)
    kint = parse(BigInt, bytes2hex(I[1:32]); base=16)
    chain = I[33:64]

    for idx in (0x80000000 + 44, 0x80000000 + 0, 0x80000000 + 0, 0x80000000 + 0)
        data = vcat(UInt8[0x00], _big2bytes32(kint),
                    UInt8[(idx >> 24) & 0xFF, (idx >> 16) & 0xFF, (idx >> 8) & 0xFF, idx & 0xFF])
        I = hmac_sha512(chain, data)
        kint = (parse(BigInt, bytes2hex(I[1:32]); base=16) + kint) % N_CURVE
        chain = I[33:64]
    end
    data = vcat(_big2bytes32(kint), UInt8[0x00, 0x00, 0x00, 0x00])
    I = hmac_sha512(chain, data)
    kint = (parse(BigInt, bytes2hex(I[1:32]); base=16) + kint) % N_CURVE
    return kint
end

# ── Endereço comprimido P2PKH ──────────────────────────────

function ripemd160(data::Vector{UInt8})::Vector{UInt8}
    out = zeros(UInt8, 20)
    ccall((:RIPEMD160, "libcrypto"), Ptr{Cvoid}, (Ptr{UInt8}, Csize_t, Ptr{UInt8}), data, length(data), out)
    return out
end

function sha256d(data::Vector{UInt8})::Vector{UInt8}
    return Vector{UInt8}(SHA.sha256(SHA.sha256(data)))
end

const BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

function base58encode(bytes::Vector{UInt8})::String
    x = BigInt(0)
    for b in bytes
        x = x * 256 + b
    end
    out = Char[]
    while x > 0
        x, r = divrem(x, 58)
        pushfirst!(out, BASE58[r + 1])
    end
    for b in bytes
        b != 0x00 && break
        pushfirst!(out, '1')
    end
    return String(out)
end

"""
    derive_address(words, idxmap)::String
Endereço Bitcoin comprimido (P2PKH) na derivação m/44'/0'/0'/0/0.
"""
function derive_address(words::Vector{String}, idxmap::Dict{String,Int})::String
    k = derive_private_key_bip32(words, idxmap)
    pub = Secp256k1.serialize(k * Secp256k1.G, compressed=true)
    h160 = ripemd160(Vector{UInt8}(SHA.sha256(pub)))
    ext = vcat(UInt8[0x00], h160)
    full = vcat(ext, sha256d(ext)[1:4])
    return base58encode(full)
end

# ── Brute-force por posições desconhecidas ──────────────────

"""
    brute_unknown_positions(known, wordlist, im; target="", nthreads)
Procura combinações de palavras para as posições conhecidas que geram o endereço-alvo.

- `known`: vetor de 12 Strings; use `""` nas posições a preencher.
- `wordlist`: wordlist BIP39 (2048 palavras).
- `im`: index_map(wordlist).
- `target`: endereço alvo (P2PKH). Se vazio, lista todas as combinações com checksum válido.
- `threads`: número de threads; 0 => Threads.nthreads().
"""
function brute_unknown_positions(known::Vector{String}, wordlist::Vector{String},
                                 im::Dict{String,Int}, target::String=""; threads::Int=0)
    n = length(known)
    unknown = findall(w -> w == "", known)
    isempty(unknown) && (unknown = [n])

    if length(unknown) > 3
        error("$(length(unknown)) posições desconhecidas: normalmente inviável (2048^$(length(unknown))). Reduza.")
    end

    hits = String[]
    locks = ReentrantLock()
    wordlen = length(wordlist)
    total = wordlen ^ length(unknown)

    @threads for i in 1:total
        # decodifica i -> índices das posições desconhecidas
        comb = Vector{UInt16}(undef, length(unknown))
        acc = i - 1
        for j in 1:length(unknown)
            acc, r = divrem(acc, wordlen)
            comb[j] = UInt16(r + 1)
        end
        w = copy(known)
        for (slot, c) in zip(unknown, comb)
            w[slot] = wordlist[c]
        end
        if !checksum_valid(w, im)
            continue
        end
        if isempty(target) || derive_address(w, im) == target
            lock(locks) do
                push!(hits, join(w, " "))
            end
        end
    end
    return hits
end

end # module