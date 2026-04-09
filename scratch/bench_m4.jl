
using Pkg; Pkg.activate(".")
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

# Carregamento correto baseado no main.jl
include("../src/Config.jl")
include("../src/Base58.jl")
include("../src/BtcCrypto.jl")
include("../src/BtcUtils.jl")
include("../src/CheckpointManager.jl")
include("../src/PuzzleData.jl")
include("../src/BloomFilter.jl")
include("../src/MultiTarget.jl")
include("../src/FastField.jl")
include("../src/FastSecp.jl")
include("../src/engines/Engines.jl")
include("../src/scanner/ScannerOrchestrator.jl")
include("../src/UI.jl")

using .ConfigModule
using .ScannerOrchestrator
using .Engines
using .BtcCrypto
using .MultiTarget
using Dates

function auto_bench()
    println("--- BENCHMARK AUTOMÁTICO (M4 OPTIMIZED) ---")
    
    # Configuração ideal para M4
    CFG = ConfigModule.load_settings()
    CFG.cpus = 4
    CFG.batch_size = 16384
    CFG.engine = :bitcrack
    
    target_addr = "11p6T996UqVpDAbN6U6AnG89A4tQ5w5m7" # Exemplo puzzle #1
    
    println("Config: Threads=$(CFG.cpus), Buffer=$(CFG.batch_size)")
    println("Iniciando benchmark de 20 segundos...")
    
    stop_signal = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    
    # Setup do motor
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    n_threads = CFG.cpus
    batch_sz = CFG.batch_size
    start_key = BigInt(rand(0x10000000:0x1fffffff))
    
    t_start = now()
    
    workers = map(1:n_threads) do wid
        Threads.@spawn begin
            curr_base = start_key + BigInt((wid - 1) * batch_sz)
            stride = Int(batch_sz * n_threads)
            # Acessando o motor via Engines
            state = Engines.BitCrackEngine.init_engine(curr_base, target_set, batch_sz, stride, false)
            
            local_count = 0
            while !stop_signal[]
                idx, h = Engines.BitCrackEngine.check_batch(state)
                local_count += batch_sz
                if local_count >= 128 * batch_sz
                    Threads.atomic_add!(keys_done, local_count)
                    local_count = 0
                end
                Engines.BitCrackEngine.next_batch!(state)
            end
            Threads.atomic_add!(keys_done, local_count)
        end
    end
    
    # Monitorar por 20 segundos
    for i in 1:20
        sleep(1)
        elapsed = (now() - t_start).value / 1000.0
        cur_keys = keys_done[]
        speed = cur_keys / elapsed / 1e6
        print("\rTempo: $(i)s | Velocidade: $(round(speed, digits=2)) M/s")
    end
    
    stop_signal[] = true
    foreach(wait, workers)
    
    t_end = now()
    total_keys = keys_done[]
    elapsed = (t_end - t_start).value / 1000.0
    final_speed = total_keys / elapsed / 1e6
    
    println("\n\n--- RESULTADO FINAL ---")
    println("Total de Chaves: $(total_keys)")
    println("Tempo: $(round(elapsed, digits=2)) s")
    println("Velocidade Média: $(round(final_speed, digits=2)) M/s")
    
    if final_speed > 4.0
        println("SUCESSO: Meta de 4M/s atingida!")
    else
        println("ALERTA: Ainda abaixo da meta. Analisando gargalos...")
    end
end

auto_bench()
