# ═══════════════════════════════════════════════════════════
#  solve_bip39.jl · Solucionador de puzzles BIP39 -> BIP32 m/44'/0'/0'/0/0
#  Uso:
#    julia --project=. -t <threads> solve_bip39.jl
#  Edite as variáveis TARGET e KNOWN abaixo (posições vazias = "").
# ═══════════════════════════════════════════════════════════
using Pkg; Pkg.activate(".")

include("src/Bip39Solver.jl")
using .Bip39Solver

# ── Configuração ─────────────────────────────────────────────
const WORDLIST_PATH = "/Users/samuel.oliveirabra/Documents/Desafio Bitcoin/palavras.txt"
const TARGET = "1BJwHmnLrEYCZ1sPrdEdzdadeacPzBs5Zb"   # endereço alvo
# Posições que você leu da imagem; use "" nas desconhecidas
KNOWN = ["faith", "meat", "evil", "donkey", "donor", "similar",
         "oxygen", "oval", "friend", "popular", "venture", ""]

wrds = load_wordlist(WORDLIST_PATH)
im   = index_map(wrds)

println("Buscando combinações que geram: $TARGET")
@time hits = brute_unknown_positions(KNOWN, wrds, im, String(strip(TARGET)))
if isempty(hits)
    println("\n✗ Nenhuma combinação batera o endereço. Veja: as palavras lidas ou a ordem estão erradas.")
else
    println("\n✓ Solução(s) possível(eis):")
    foreach(println, hits)
end