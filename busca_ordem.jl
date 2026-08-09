# ═══════════════════════════════════════════════════════════
#  busca_ordem.jl · Busca a ORDEM correta de 12 palavras BIP39
#  Filtro-checksum PRIMEIRO (técnica-chave) + derivação via libcrypto.
#  Entrada: 12 palavras como args → acha a permutação que dá TARGET.
# ═══════════════════════════════════════════════════════════
using Pkg; Pkg.activate(".")
using SHA
import Secp256k1

const TARGET = "1BJwHmnLrEYCZ1sPrdEdzdadeacPzBs5Zb"
const WORDLIST_PATH = "/Users/samuel.oliveirabra/Documents/Desafio Bitcoin/palavras.txt"
const NCURVE = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"; base=16)

const EVP512 = Ref{Ptr{Cvoid}}()
function _init()
    EVP512[] = ccall((:EVP_sha512, "libcrypto"), Ptr{Cvoid}, ())
end

function pbkdf2_sha512(pass::Vector{UInt8}, salt::Vector{UInt8}, iters::Int, dklen::Int)
    out = zeros(UInt8, dklen)
    ccall((:PKCS5_PBKDF2_HMAC, "libcrypto"), Cint,
          (Ptr{UInt8}, Cint, Ptr{UInt8}, Cint, Cint, Ptr{Cvoid}, Cint, Ptr{UInt8}),
          pass, length(pass), salt, length(salt), iters, EVP512[], dklen, out)
    return out
end

function hmac_sha512(key::Vector{UInt8}, data::Vector{UInt8})
    d = zeros(UInt8, 64)
    ccall((:HMAC, "libcrypto"), Ptr{Cvoid},
          (Ptr{Cvoid}, Ptr{UInt8}, Cint, Ptr{UInt8}, Csize_t, Ptr{UInt8}, Ptr{Csize_t}),
          EVP512[], key, length(key), data, length(data), d, C_NULL)
    return d
end

function sha256_bytes(data::Vector{UInt8})
    return Vector{UInt8}(SHA.sha256(data))
end

function ripemd160(data::Vector{UInt8})
    out = zeros(UInt8, 20)
    ccall((:RIPEMD160, "libcrypto"), Ptr{Cvoid},
          (Ptr{UInt8}, Csize_t, Ptr{UInt8}), data, length(data), out)
    return out
end

function big2bytes32(n::BigInt)
    out = zeros(UInt8, 32)
    for i in 32:-1:1
        out[i] = UInt8(n & 0xFF); n >>= 8
    end
    return out
end

const BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
function base58encode(bytes::Vector{UInt8})
    x = BigInt(0)
    for b in bytes; x = x * 256 + b; end
    out = Char[]
    while x > 0
        x, r = divrem(x, 58); pushfirst!(out, BASE58[r + 1])
    end
    for b in bytes
        b != 0x00 && break; pushfirst!(out, '1')
    end
    return String(out)
end

# ── Derivação completa ─────────────────────────────────────
function derive_address(words::Vector{String}, im::Dict{String,Int})
    frase = join(words, " ")
    seed = pbkdf2_sha512(Vector{UInt8}(frase), Vector{UInt8}("mnemonic"), 2048, 64)
    I = hmac_sha512(Vector{UInt8}("Bitcoin seed"), seed)
    kint = parse(BigInt, bytes2hex(I[1:32]); base=16)
    chain = I[33:64]
    for idx in (0x80000000 + 44, 0x80000000, 0x80000000, 0x80000000)
        data = vcat(UInt8[0x00], big2bytes32(kint),
                    UInt8[(idx>>24)&0xFF, (idx>>16)&0xFF, (idx>>8)&0xFF, idx&0xFF])
        I = hmac_sha512(chain, data)
        kint = (parse(BigInt, bytes2hex(I[1:32]); base=16) + kint) % NCURVE
        chain = I[33:64]
    end
    data = vcat(big2bytes32(kint), UInt8[0x00, 0x00, 0x00, 0x00])
    I = hmac_sha512(chain, data)
    kint = (parse(BigInt, bytes2hex(I[1:32]); base=16) + kint) % NCURVE
    pub = Secp256k1.serialize(kint * Secp256k1.G, compressed=true)
    h160 = ripemd160(sha256_bytes(pub))
    ext = vcat(UInt8[0x00], h160)
    full = vcat(ext, sha256_bytes(sha256_bytes(ext))[1:4])
    return base58encode(full)
end

# ── rank → permutação ─────────────────────────────────────
function fact(n::Int)
    n <= 1 ? 1 : n * fact(n - 1)
end

function perm_from_rank(bag::Vector{String}, rank::Int)::Vector{String}
    n = length(bag)
    elems = collect(bag)
    res = Vector{String}(undef, n)
    k = rank
    for i in 1:n
        f = fact(n - i)
        idx = div(k, f) % length(elems) + 1
        res[i] = elems[idx]
        deleteat!(elems, idx)
    end
    return res
end

# ── Checksum BIP39 (132 bits) ──────────────────────────────
function checksum_valid(words::Vector{String}, im::Dict{String,Int})::Bool
    io = IOBuffer()
    for w in words
        print(io, string(im[w], base=2, pad=11))
    end
    bits = String(take!(io))
    ent = parse(UInt128, bits[1:end-4]; base=2)
    cs  = bits[end-3:end]
    entbytes = zeros(UInt8, 16)
    for i in 16:-1:1
        entbytes[i] = UInt8(ent & 0xFF); ent >>= 8
    end
    h = sha256_bytes(entbytes)
    return string(h[1], base=2, pad=8)[1:4] == cs
end

# ── main ───────────────────────────────────────────────────
function main(args)
    isempty(args) && error("Uso: julia busca_ordem.jl WORD1..WORD12 (ordem não importa)")
    bag = String[String(strip(a)) for a in args]
    length(bag) != 12 && error("preciso exatamente 12 palavras")
    im = Dict{String,Int}()
    for (i, w) in enumerate(readlines(WORDLIST_PATH))
        im[w] = i - 1
    end
    for w in bag
        haskey(im, w) || throw(ArgumentError("palavra sem wordlist: '$w'"))
    end
    total = fact(12)
    println("Buscando a ordem de ", join(bag, " "), " — total ", total, " permutações, threads=", Threads.nthreads())
    found = String[]
    lock = ReentrantLock()
    _init()
    done = Threads.Atomic{Int}(0)
    t0 = time()
    Threads.@threads for r in 0:(total-1)
        perm = perm_from_rank(bag, r)
        if checksum_valid(perm, im) && derive_address(perm, im) == TARGET
            lock(lock) do
                push!(found, join(perm, " "))
            end
        end
        if Threads.atomic_add!(done, 1) % 2_000_000 == 1
            el = time() - t0
            rate = done[] / el
            print("\r  progresso: $(done[]) / $(total)   rate: $(round(Int, rate))/s   eta: $(round((total-done[])/rate/60, digits=1))min   ")
        end
    end
    if isempty(found)
        println("\n✗ Nenhuma ordem gera o alvo.")
    else
        println("\n✓ SOLUÇÃO:"); foreach(println, "  " .* found)
    end
end
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
