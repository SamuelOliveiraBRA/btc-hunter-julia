using Pkg; Pkg.activate(".")
println("\n" * "═"^64)
println("   🚀 FINAL M4 PERFORMANCE SWEEP — BITCOIN HUNTER v1.5")
println("═"^64)

# Importar ambiente necessário na ordem correta
include("src/Config.jl")
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/BtcUtils.jl")
include("src/CheckpointManager.jl")
include("src/PuzzleData.jl")
include("src/BloomFilter.jl")
include("src/MultiTarget.jl")
include("src/FastField.jl")
include("src/SecpOptimized.jl") 
include("src/FastSecp.jl")
include("src/FastRipemd.jl")
include("src/GpuCrypto.jl")
include("src/engines/Engines.jl")
include("src/UI.jl")

using .ConfigModule, .BtcCrypto, .MultiTarget, .Engines, .UIModule
using Dates, Printf, Random

function run_test(workers, buffer)
    # Alvo fixo para o teste (Puzzle 20)
    target_addr = "1HsMJxNiV7TLxmoF6uJNkydxPFDog4NQum"
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    stop = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    start_key = BigInt(0x80000)
    
    # ── Trabalhadores ──
    v_workers = map(1:workers) do wid
        Threads.@spawn begin
            curr = start_key + BigInt((wid - 1) * buffer)
            stride = Int(buffer * workers)
            # NOVO PADRÃO: init_engine(..., both_formats, stride_size)
            state = Engines.BitCrackEngine.init_engine(curr, target_set, buffer, false, stride)
            
            local_c = 0
            while !stop[]
                res = Engines.BitCrackEngine.check_batch(state)
                local_c += buffer
                # Update atômico a cada 256 lotes para não gargalar
                if local_c >= 256 * buffer
                    Threads.atomic_add!(keys_done, local_c)
                    local_c = 0
                end
                Engines.BitCrackEngine.next_batch!(state)
            end
            Threads.atomic_add!(keys_done, local_c)
        end
    end
    
    # Teste de 15 segundos para garantir estabilidade e precisão
    sleep(15) 
    stop[] = true
    foreach(wait, v_workers)
    
    keys_tot = keys_done[]
    speed = keys_tot / 15.0 / 1e6 # Mkeys/s
    return speed
end

function main()
    WORKERS = [4, 6, 8, 10]
    BUFFERS = [16384, 32768, 65536, 102400, 131072]
    
    results = []
    
    total_tests = length(WORKERS) * length(BUFFERS)
    curr_test = 0
    
    for w in WORKERS
        for b in BUFFERS
            curr_test += 1
            @printf("  [%d/%d] Testando Workers: %d | Buffer: %6d ... ", 
                    curr_test, total_tests, w, b)
            
            try
                s = run_test(w, b)
                @printf(" SPEED: %.3f M/s\n", s)
                push!(results, (w=w, b=b, s=s))
            catch e
                @printf(" ERRO\n")
            end
        end
    end
    
    sort!(results, by=x->x.s, rev=true)
    
    # Salvar resultados
    ranking_file = "data/m4_performance_ranking.md"
    mkpath("data")
    
    open(ranking_file, "w") do io
        write(io, "# Ranking de Performance Apple M4\n\n")
        write(io, "| Rank | Workers | Buffer | Velocidade | Obs |\n")
        write(io, "|------|---------|--------|------------|-----|\n")
        for (i, r) in enumerate(results)
            write(io, "| #$i | $(r.w) | $(r.b) | $(round(r.s, digits=3)) M/s | $(i==1 ? "**WINNER**" : "") |\n")
        end
        write(io, "\nAuto-gerado em: $(now())\n")
    end
    
    println("\n" * "═"^64)
    println("  🏁 VARREDURA CONCLUÍDA")
    println("  Ranking salvo em: $ranking_file")
    if !isempty(results)
        best = results[1]
        @printf("  🏆 MELHOR CONFIGURAÇÃO: %d Workers | Buffer %d --> %.3f M/s\n", 
                best.w, best.b, best.s)
    end
    println("═"^64)
end

main()
