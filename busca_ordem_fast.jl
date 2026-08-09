# ═══════════════════════════════════════════════════════════
#  busca_ordem_fast.jl
#  Busca a ORDEM correta de 12 palavras BIP39 → BIP32 m/44'/0'/0'/0/0
#  Motor: permutação por RANK com partição por faixa (paralela),
#  filtro-checksum primeiro, derivação via libcrypto.
#  Uso: julia --project=. -t auto busca_ordem_fast.jl W1 W2 ... W12
# ═══════════════════════════════════════════════════════════
using Pkg; Pkg.activate(".")
using SHA
import Secp256k1

const TARGET = "1BJwHmnLrEYCZ1sPrdEdzdadeacPzBs5Zb"
const WORDLIST_PATH = "/Users/samuel.oliveirabra/Documents/Desafio Bitcoin/palavras.txt"
const NCURVE = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"; base=16)
const FACT = Int[1,1,2,6,24,120,720,5040,40320,362880,3628800,39916800,479001600]

const EVP512 = Ref{Ptr{Cvoid}}()
function _init()
    EVP512[] = ccall((:EVP_sha512, "libcrypto"), Ptr{Cvoid}, ())
end
_init()

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

# derivação completa a partir de um vetor de STRINGS já na ordem
function derive_address(words::Vector{String})
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

function checksum_valid_words(words::Vector{String}, im::Dict{String,Int})
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

function perm_from_rank(bag::Vector{String}, k::Int)
    n = length(bag)
    elems = collect(bag)
    res = Vector{String}(undef, n)
    kk = k
    for i in 1:n
        f = FACT[n - i + 1]
        idx = div(kk, f) % length(elems) + 1
        res[i] = elems[idx]
        deleteat!(elems, idx)
    end
    return res
end

function main(args)
    isempty(args) && error("Uso: julia busca_ordem_fast.jl W1..W12 (ordem não importa)")
    bag = String[String(strip(a)) for a in args]
    length(bag) != 12 && error("preciso 12 palavras")
    im = Dict{String,Int}()
    for (i, w) in enumerate(readlines(WORDLIST_PATH))
        im[w] = i - 1
    end
    for w in bag
        haskey(im, w) || throw(ArgumentError("palavra fora da wordlist: '$w'"))
    end

    total = FACT[13]
    println("Buscando ordem de: ", join(bag, " "))
    println("  total: ", total, " permutações | threads: ", Threads.nthreads())
    flush(stdout)

    nt = Threads.nthreads()
    found = String[]
    lock = ReentrantLock()
    done = Threads.Atomic{Int}(0)
    t0 = time()

    chunk = cld(total, nt)
    Threads.@threads for tid in 1:nt
        a = (tid - 1) * chunk
        b = min(tid * chunk, total) - 1
        for r in a:b
            perm = perm_from_rank(bag, r)
            if checksum_valid_words(perm, im) && derive_address(perm) == TARGET
                Threads.lock(lock) do
                    push!(found, join(perm, " "))
                end
            end
            c = Threads.atomic_add!(done, 1)
            if c % 1_000_000 == 0
                el = time() - t0
                rate = c / el
                local n = (rate == 0.0 ? 0 : round(Int, 8e0))
                println("PROGRESS $total $c rate=$(round(rate)) eta_min=$(round((total-c)/rate/60, digits=1))")
                flush(stdout)
            end
        end
    end
    print("\n")
    if isempty(found)
        println("✗ Nenhuma ordem gera o alvo: ", TARGET)
    else
        println("✓ SOLUÇÃO:")
        foreach(println, "  " .* found)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end