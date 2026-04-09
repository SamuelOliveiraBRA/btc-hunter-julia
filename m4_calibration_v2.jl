
using Pkg; Pkg.activate(".")
println("--- INICIALIZANDO SUPER-CALIBRADOR M4 (V2) ---")

# Inclusão completa
include("src/Config.jl")
using .ConfigModule
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/BtcUtils.jl")
include("src/CheckpointManager.jl")
include("src/PuzzleData.jl")
include("src/BloomFilter.jl")
include("src/MultiTarget.jl")
using .Base58, .BtcCrypto, .BtcUtils, .CheckpointManager, .PuzzleData, .BloomFilter, .MultiTarget
include("src/SecpOptimized.jl") 
include("src/FastField.jl")
include("src/FastSecp.jl")
include("src/GpuCrypto.jl")
using .FastField, .FastSecp
include("src/UI.jl")
using .UIModule
include("src/engines/Engines.jl")
using .Engines
include("src/scanner/ScannerOrchestrator.jl")
using .ScannerOrchestrator

using Dates, Printf, Random

function run_advanced_test(workers_count, buffer_size, sim_ui_load::Bool)
    println("\n> Teste: Workers=$workers_count | Buffer=$buffer_size | UI_Sim=$sim_ui_load")
    
    target_addr = "19EEC52krRUK1RkUAEZmQdjTyHT7Gp1TYT" 
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    stop = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    start_key = BigInt(0x1121d0000)
    
    # ── Simulação de Carga de UI ─────────────────────────
    if sim_ui_load
        Threads.@spawn begin
            while !stop[]
                # Simula o processamento do loop de UI (print, formatação, etc)
                # O Dashboard real atualiza a cada 5s, mas faz processamento de strings
                UIModule.fmt_num(rand(1:1_000_000_000))
                UIModule.progress_bar(rand(1:100), 100)
                sleep(0.5) # Mais frequente que o real para estressar
            end
        end
    end

    t_start = now()
    
    # ── Trabalhadores de Busca ───────────────────────────
    workers = map(1:workers_count) do wid
        Threads.@spawn begin
            curr = start_key + BigInt((wid - 1) * buffer_size)
            stride = Int(buffer_size * workers_count)
            state = Engines.BitCrackEngine.init_engine(curr, target_set, buffer_size, false, stride)
            
            local_c = 0
            while !stop[]
                res = Engines.BitCrackEngine.check_batch(state)
                local_c += buffer_size
                if local_c >= 256 * buffer_size
                    Threads.atomic_add!(keys_done, local_c)
                    local_c = 0
                end
                Engines.BitCrackEngine.next_batch!(state)
            end
            Threads.atomic_add!(keys_done, local_c)
        end
    end
    
    sleep(10) # 10 segundos para estabilizar
    stop[] = true
    foreach(wait, workers)
    
    elapsed = (now() - t_start).value / 1000.0
    speed = keys_done[] / elapsed / 1e6
    return speed
end

function main_sweep()
    # Testar com mais threads disponíveis no sistema (-t 10)
    # Mas variando quantos processos de busca ativos
    worker_options = [3, 4, 5] 
    buffer_options = [12288, 16384, 20480] # Testando arredores de 16k
    
    println("Threads totais disponíveis: $(Threads.nthreads())")
    
    results = []
    
    for w in worker_options
        for b in buffer_options
            s = run_advanced_test(w, b, true)
            push!(results, (w=w, b=b, s=s))
            @printf("  SPEED: %.2f M/s\n", s)
        end
    end
    
    sort!(results, by=x->x.s, rev=true)
    
    println("\n" * "═"^60)
    println("  FINAL RANKING (M4 OPTIMIZATION V2)")
    println("═"^60)
    for (i, r) in enumerate(results)
        @printf("  #%d | Workers: %d | Buffer: %5d | %.2f M/s\n", i, r.w, r.b, r.s)
    end
    
    if !isempty(results)
        best = results[1]
        println("\n🏆 VENCEDOR DEFINITIVO: $(best.w) Workers com Buffer $(best.b)")
        # Sugerir comando
        println("\nComando recomendado:")
        println("julia -t 10 main.jl (Com configurar CPUs=$(best.w) e Buffer=$(best.b))")
    end
end

main_sweep()
