module PuzzleData

using JSON

export Puzzle, get_puzzle, ALL_PUZZLES

struct Puzzle
    number::Int
    address::String
    pubkey::String  # Pode ser vazia se não configurada no ranges.json
    start_range::BigInt
    end_range::BigInt
end

# Caminho para o arquivo de configuração de ranges
const _RANGES_FILE = joinpath(@__DIR__, "..", "data", "ranges.json")

"""
    _load_all_puzzles()
Carrega todos os puzzles dinamicamente do `data/ranges.json`.
Nenhum dado de carteira ou pubkey é hardcoded aqui.
"""
function _load_all_puzzles()::Dict{Int, Puzzle}
    result = Dict{Int, Puzzle}()
    try
        ranges = JSON.parsefile(_RANGES_FILE)["ranges"]
        for (i, r) in enumerate(ranges)
            addr   = get(r, "endereco", "")
            pubkey = get(r, "pubkey",   "")
            r_min  = parse(BigInt, replace(get(r, "min", "0x1"), "0x" => "", "0X" => ""), base=16)
            r_max  = parse(BigInt, replace(get(r, "max", "0x1"), "0x" => "", "0X" => ""), base=16)
            result[i] = Puzzle(i, addr, pubkey, r_min, r_max)
        end
    catch e
        @warn "Erro ao carregar ranges.json em PuzzleData: $e"
    end
    return result
end

# Dicionário global carregado uma vez na inicialização do módulo
const ALL_PUZZLES = _load_all_puzzles()

"""
    get_puzzle(n::Int)
Retorna as informações do puzzle pelo seu número.
Lê do ranges.json — sem dados hardcoded.
"""
function get_puzzle(n::Int)::Puzzle
    if haskey(ALL_PUZZLES, n)
        return ALL_PUZZLES[n]
    else
        # Puzzle fora do ranges.json: calcula o range matematicamente
        r_start = BigInt(2)^(n - 1)
        r_end   = (BigInt(2)^n) - 1
        return Puzzle(n, "", "", r_start, r_end)
    end
end

end # module
