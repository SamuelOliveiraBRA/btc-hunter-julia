# ═══════════════════════════════════════════════════════════
#  solve_bip39_menu.jl · Menu interativo
#  Puzzle BIP39 → BIP32 m/44'/0'/0'/0/0 (P2PKH comprimido)
#
#  Uso:
#    julia --project=. -t auto solve_bip39_menu.jl
# ═══════════════════════════════════════════════════════════
using Pkg; Pkg.activate(".")
import SHA, Secp256k1
include("src/Bip39Solver.jl")
using .Bip39Solver

const WORDLIST_PATH = "/Users/samuel.oliveirabra/Documents/Desafio Bitcoin/palavras.txt"
const TARGET = "1BJwHmnLrEYCZ1sPrdEdzdadeacPzBs5Zb"

wrds = load_wordlist(WORDLIST_PATH)   # 2048 palavras BIP39
im   = index_map(wrds)

# ── util: fatorial ──────────────────────────────────────────
function fact(n::Int)
    n <= 1 ? 1 : n * fact(n - 1)
end

# ── Modo 1: 12 palavras, ordem fixa (com checksum/brute) ───
function modo_fixo()
    println("\n── MODO 1 · 12 palavras com ordem fixa ──")
    println("  Deixe vazio a posição desconhecida (o solver busca a 12ª/checksum).")
    known = String[]
    for k in 1:12
        print("  palavra ($k): ")
        push!(known, strip(readline(stdin)))
    end
    hits = brute_unknown_positions(known, wrds, im, TARGET)
    if isempty(hits)
        println("  ✗ Nenhuma combinação gerou o endereço-alvo.")
    else
        println("  ✓ SOLUÇÃO:")
        foreach(println, "    " .* hits)
    end
end

# ── Modo 2: buscar ORDEM com 12 palavras conhecidas ─────────
function nth_perm(bag::Vector{String}, rank::Int)::Vector{String}
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

function buscar_ordem(bag::Vector{String}, alvo::String)
    n = length(bag)
    if n != 12
        println("  Este modo precisa das 12 palavras (tem $n).")
        return
    end
    if any(w -> !haskey(im, w), bag)
        println("  ⚠ Alguma palavra não está na wordlist BIP39.")
        return
    end
    total = fact(n)
    println("\n  ", "─"^(68))
    st = time()
    local hits = 0
    Threads.@threads for i in 1:(total - 1)
    end
    nothing
end

# ── esconde-ideas ──────────────────────────────────────────