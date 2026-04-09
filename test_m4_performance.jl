
using Pkg; Pkg.activate(".")
push!(LOAD_PATH, joinpath(@__DIR__, "src"))

# Carregamento correto baseado no main.jl
include("src/Config.jl")
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/BtcUtils.jl")
include("src/CheckpointManager.jl")
include("src/PuzzleData.jl")
include("src/BloomFilter.jl")
include("src/MultiTarget.jl")
include("src/FastField.jl")
include("src/FastSecp.jl")
include("src/engines/Engines.jl")
include("src/scanner/ScannerOrchestrator.jl")
include("src/UI.jl")

using .ConfigModule
using .ScannerOrchestrator
using .Engines
using .BtcCrypto
using .MultiTarget
using Dates

function run_single_test(threads, buffer)
    println("\n> Testando: Threads=$threads, Buffer=$buffer")
    
    CFG = ConfigModule.load_settings()
    CFG.cpus = threads
    CFG.batch_size = buffer
    CFG.engine = :bitcrack
    
    # Endereço de teste (Puzzle #10 - 268M chaves)
    target_addr = "11p6T996UqVpDAbN6U6AnG89A4tQ5w5m7" 
    
    stop_signal = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    
    # Setup do motor com LUT ativa
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    n_threads = threads
    batch_sz = buffer
    start_key = BigInt(0x10000000 + rand(1:1000000)) # Ponto aleatório no puzzle #10
    
    t_start = now()
    
    workers = map(1:n_threads) do wid
        Threads.@spawn begin
            curr_base = start_key + BigInt((wid - 1) * batch_sz)
            stride = Int(batch_sz * n_threads)
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
    
    # Medir por 10 segundos
    sleep(10)
    stop_signal[] = true
    foreach(wait, workers)
    
    elapsed = (now() - t_start).value / 1000.0
    speed = keys_done[] / elapsed / 1e6
    return speed
end

function main_bench()
    println("╔══════════════════════════════════════════════════════════════╗")
    println("║     BTC HUNTER - BATERIA DE TESTES AUTOMÁTICA (M4)           ║")
    println("╚══════════════════════════════════════════════════════════════╝")
    
    # Grade de testes
    thread_options = [4, 6]            # M4 tem 4 cores de performance
    buffer_options = [8192, 16384, 32768]
    
    results = []
    
    for t in thread_options
        for b in buffer_options
            speed = run_single_test(t, b)
            push!(results, (t=t, b=b, s=speed))
            println("  RESULTADO: $(round(speed, digits=2)) M/s")
        end
    end
    
    println("\n\n╔══════════════════════════════════════════════════════════════╗")
    println("║            RANKING DE PERFORMANCE (M/s)                      ║")
    println("╚══════════════════════════════════════════════════════════════╝")
    
    sort!(results, by=x->x.s, rev=true)
    
    for (i, r) in enumerate(results)
        medal = i == 1 ? "🥇" : i == 2 ? "🥈" : "  "
        @printf("%s #%d | Threads: %d | Buffer: %5d | Velocidade: %.2f M/s\n", 
                medal, i, r.t, r.b, r.s)
    end
    
    best = results[1]
    println("\n🏆 CONFIGURAÇÃO VENCEDORA: Threads=$(best.t), Buffer=$(best.b)")
    
    # Salvar a melhor configuração
    CFG = ConfigModule.load_settings()
    CFG.cpus = best.t
    CFG.batch_size = best.b
    ConfigModule.save_settings(CFG)
    println("\n✅ Configuração salva permanentemente no settings.json!")
end

main_bench()
