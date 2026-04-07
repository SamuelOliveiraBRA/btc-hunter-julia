module ConfigModule

export Config, CFG

using JSON

mutable struct Config
    cpus::Int
    internet::Bool
    gpu::Bool
    gpu_intensity::Int
    wallet_num::Int
    wallet_addr::String
    wallet_status::Int
    interval_min::String
    interval_max::String
    saldo::String
    mode::Int
    running::Bool
    batch_size::Int
    both_formats::Bool
    use_checkpoint::Bool
    checkpoint_interval::Int
    engine::Symbol
end

const SETTINGS_FILE = "config/settings.json"

function save_settings(cfg::Config)
    try
        mkpath("config")
        open(SETTINGS_FILE, "w") do f
            JSON.print(f, cfg, 4)
        end
    catch e
        @warn "Erro ao salvar configurações: $e"
    end
end

function load_settings()
    # Padrões iniciais
    default_cfg = Config(
        Sys.CPU_THREADS, false, false, 1, 0, "", 0,
        "0x0", "0x0", "", 0, true, 512, false, true, 30, :secp
    )

    if !isfile(SETTINGS_FILE)
        return default_cfg
    end

    try
        data = JSON.parsefile(SETTINGS_FILE)
        # Mapeia JSON para a struct (tratando símbolos adequadamente)
        for field in fieldnames(Config)
            f_str = string(field)
            if haskey(data, f_str)
                val = data[f_str]
                if field == :engine
                    setfield!(default_cfg, field, Symbol(val))
                else
                    setfield!(default_cfg, field, convert(fieldtype(Config, field), val))
                end
            end
        end
        return default_cfg
    catch e
        @warn "Erro ao carregar configurações: $e. Usando padrões."
        return default_cfg
    end
end

const CFG = load_settings()

end # module
