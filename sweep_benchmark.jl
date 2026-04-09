using Dates
using Printf

# ═══════════════════════════════════════════════════════════
#  SWEEP BENCHMARK (Mac M4 Otimização)
# ═══════════════════════════════════════════════════════════

function run_benchmark()
    THREADS = [4, 8, 10]
    BATCHES = [2048, 8192, 16384, 32768, 65536, 131072]
    
    results_file = "data/benchmark_results.md"
    mkpath("data")
    
    if !isfile(results_file)
        open(results_file, "w") do io
            write(io, "# Resultados da Varredura de Performance (Mac M4)\n\n")
            write(io, "| Threads | Batch Size | Resultado | Obs |\n")
            write(io, "|---------|------------|-----------|-----|\n")
        end
    end

    julia_bin = "/Users/samuel.oliveirabra/.juliaup/bin/julia"

    for t in THREADS
        for b in BATCHES
            println("\n$(Dates.now()) ══════════════════════════════════════")
            println("  TESTANDO: Threads: $t | Batch: $b")
            println("  ══════════════════════════════════════════════")
            
            # Comando para rodar silêncio e fechar
            # Usamos o Puzzle 20 pois é rápido de encontrar para teste
            cmd = `bash -c "echo '' | $julia_bin main.jl --motor bitcrack --puzzle 20 --cpus $t --batch $b"`
            
            t0 = time()
            try
                run(cmd)
                elapsed = time() - t0
                status = "SUCESSO"
                
                # Registrar na tabela
                open(results_file, "a") do io
                    write(io, "| $t | $b | $status | Tempo: $(round(elapsed, digits=2))s |\n")
                end
                println("\n  [OK] Concluído em $(round(elapsed, digits=2))s")
                
            catch e
                println("\n  [ERRO] Falha na combinação T:$t B:$b")
                open(results_file, "a") do io
                    write(io, "| $t | $b | FALHA | Erro: $e |\n")
                end
            end
        end
    end
    
    println("\n$(Dates.now()) ══════════════════════════════════════")
    println("  VARREDURA CONCLUÍDA! Confira: $results_file")
    println("  ══════════════════════════════════════════════")
end

run_benchmark()
