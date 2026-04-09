
using Pkg; Pkg.activate(".")
println("--- INICIALIZANDO AMBIENTE DE CALIBRAÇÃO ---")

# Carregamento na ordem exata do main.jl para evitar erros de dependência
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

function run_test(threads, buffer)
    println("\n> Testando: $threads Cores | Buffer $buffer...")
    
    # Aplicar config temporária
    CFG.cpus = threads
    CFG.batch_size = buffer
    CFG.engine = :bitcrack
    
    # Puzzle #29 (Screenshot do usuário)
    target_addr = "19EEC52krRUK1RkUAEZmQdjTyHT7Gp1TYT" 
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    stop = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    
    # Ponto de partida no range do Puzzle #29
    start_k = BigInt(0x1121d0000)
    
    t_start = now()
    
    workers = map(1:threads) do wid
        Threads.@spawn begin
            curr = start_k + BigInt((wid - 1) * buffer)
            stride = Int(buffer * threads)
            state = Engines.BitCrackEngine.init_engine(curr, target_set, buffer, stride, false)
            
            local_c = 0
            while !stop[]
                res = Engines.BitCrackEngine.check_batch(state)
                idx, h = res[1], res[2]
                local_c += buffer
                
                # Sincronização periódica para evitar overhead atômico
                if local_c >= 128 * buffer
                    Threads.atomic_add!(keys_done, local_c)
                    local_c = 0
                end
                
                Engines.BitCrackEngine.next_batch!(state)
            end
            Threads.atomic_add!(keys_done, local_c)
        end
    end
    
    # 7 segundos de medição pura
    sleep(7)
    stop[] = true
    foreach(wait, workers)
    
    elapsed = (now() - t_start).value / 1000.0
    speed = keys_done[] / elapsed / 1e6
    return speed
end

function calibrate()
    # Grade de testes otimizada para Apple M4
    # M4 Pro/Max tem muitos núcleos. O base tem 10 (4 performance).
    cores_to_test = [4, 6] 
    buffer_to_test = [16384, 32768, 65536]
    
    all_results = []
    
    for c in cores_to_test
        for b in buffer_to_test
            try
                s = run_test(c, b)
                push!(all_results, (c=c, b=b, s=s))
                @printf("  Resultado: %.2f M/s\n", s)
            catch e
                println("  Erro no teste ($c, $b): $e")
            end
        end
    end
    
    # Classificação
    sort!(all_results, by=x->x.s, rev=true)
    
    println("\n" * "═"^60)
    println("  RANKING DE PERFORMANCE NO M4")
    println("═"^60)
    
    for (i, r) in enumerate(all_results)
        @printf("  #%d | %d Cores | Buffer %5d | %.2f M/s\n", i, r.c, r.b, r.s)
    end
    
    if !isempty(all_results)
        best = all_results[1]
        CFG.cpus = best.c
        CFG.batch_size = best.b
        ConfigModule.save_settings(CFG)
        println("\n🏆 VENCEDOR: $(best.c) Cores com Buffer $(best.b)")
        println("✅ Configuração salva no settings.json")
    end
end

calibrate()
