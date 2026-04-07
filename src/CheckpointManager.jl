module CheckpointManager

using JSON, Dates

export save_checkpoint, load_checkpoint, delete_checkpoint, checkpoint_path, has_checkpoint

function checkpoint_path(puzzle_id::Int)
    mkpath("outputs")
    return joinpath("outputs", "checkpoint_puzzle_$(puzzle_id).json")
end

function has_checkpoint(puzzle_id::Int)::Bool
    return isfile(checkpoint_path(puzzle_id))
end

"""
    save_checkpoint(puzzle_id, current_key, keys_done, mode, elapsed)
Salva o progresso atual em JSON. Chamado a cada 30s pelo monitor thread.
"""
function save_checkpoint(puzzle_id::Int, current_key::BigInt, keys_done::Int64, mode::Int, elapsed::Float64)
    path = checkpoint_path(puzzle_id)
    data = Dict(
        "puzzle_id"   => puzzle_id,
        "current_key" => string(current_key, base=16),
        "keys_done"   => keys_done,
        "mode"        => mode,
        "elapsed"     => elapsed,
        "saved_at"    => Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    )
    open(path, "w") do f
        JSON.print(f, data, 2)
    end
end

"""
    load_checkpoint(puzzle_id)
Retorna NamedTuple com dados do checkpoint ou `nothing` se não existir.
"""
function load_checkpoint(puzzle_id::Int)
    path = checkpoint_path(puzzle_id)
    isfile(path) || return nothing
    try
        data = JSON.parsefile(path)
        return (
            current_key = parse(BigInt, data["current_key"], base=16),
            keys_done   = Int64(data["keys_done"]),
            mode        = Int(data["mode"]),
            elapsed     = Float64(get(data, "elapsed", 0.0)),
            saved_at    = get(data, "saved_at", "desconhecido")
        )
    catch e
        @warn "Falha ao carregar checkpoint do puzzle $puzzle_id: $e"
        return nothing
    end
end

"""
    delete_checkpoint(puzzle_id)
Remove o checkpoint (chamado quando a chave é encontrada).
"""
function delete_checkpoint(puzzle_id::Int)
    path = checkpoint_path(puzzle_id)
    isfile(path) && rm(path)
end

end # module CheckpointManager
