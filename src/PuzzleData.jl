module PuzzleData

export Puzzle, get_puzzle, ALL_PUZZLES

struct Puzzle
    number::Int
    address::String
    pubkey::String # Pode ser vazia
    start_range::BigInt
    end_range::BigInt
end

# Lista de Puzzles extraída do btcpuzzle.info
# O range de cada puzzle #N é entre 2^(N-1) e (2^N) - 1.
function calculate_range(n::Int)
    start = BigInt(2)^(n-1)
    stop = (BigInt(2)^n) - 1
    return start, stop
end

# Base de Dados de Puzzles Resolvidos e Não Resolvidos
const ALL_PUZZLES = Dict{Int, Puzzle}(
    25 => Puzzle(25, "15JhYXn6Mx3oF4Y7PcTAv2wVVAuCFFQNiP", "", calculate_range(25)...),
    66 => Puzzle(66, "13zb1hQbWVsc2S7ZTZnP2G4undNNpdh5so", "", calculate_range(66)...),
    71 => Puzzle(71, "1PWo3JeB9jrGwfHDNpdGK38CRKyfzv6nL5", "", calculate_range(71)...),
    160 => Puzzle(160, "1F9wP9n86676khS76khS76khS76khS76kh", "02e0a8b039282faf6fe0fd769cfbc4b6b4cf8758ba68220eac420e32b91ddfa673", calculate_range(160)...)
)

"""
    get_puzzle(n::Int)
Retorna as informações do puzzle pelo seu número.
"""
function get_puzzle(n::Int)::Puzzle
    if haskey(ALL_PUZZLES, n)
        return ALL_PUZZLES[n]
    else
        # Calcula range dinamicamente se não estiver no dict
        s, e = calculate_range(n)
        return Puzzle(n, "", "", s, e)
    end
end

end # module
