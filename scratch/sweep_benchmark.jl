# ═══════════════════════════════════════════════════════════════════
# sweep_benchmark.jl — Automação de Stress-Test (Mac M4)
# ═══════════════════════════════════════════════════════════════════

using Printf

# Parâmetros de Sweep
THREADS = [4, 8, 10]
BATCHES = ["pequeno", "medio", "grande", "extremo"]
PUZZLE  = 20

results_file = "data/benchmark_results.md"

function run_sweep()
    io = open(results_file, "w")
    write(io, "# Resultados da Varredura de Performance (Mac M4)\n\n")
    write(io, "| Threads | Batch Size | Resultado | Obs |\n")
    write(io, "|---------|------------|-----------|-----|\n")
    close(io)
    
    for t in THREADS
        for b in BATCHES
            println("\n>>> TESTANDO: Threads = $t | Batch = $b")
            
            # Comando de execução com simulação de ENTER para fechar a sessão automaticamente
            cmd = pipeline(`echo ""`, `/opt/homebrew/bin/julia --project main.jl --puzzle $PUZZLE --engine 1 --batch $b -t $t`)
            
            start_t = time()
            process = run(cmd, wait=true)
            end_t = time()
            
            status = process.exitcode == 0 ? "✅ Encontrada" : "❌ Erro/Interrompida"
            elapsed = @sprintf("%.2fs", end_t - start_t)
            
            # Registrar na tabela
            io = open(results_file, "a")
            write(io, "| $t | $b | $status | Tempo: $elapsed |\n")
            close(io)
            
            println("<<< CONCLUÍDO: $status em $elapsed")
            sleep(1) # Resfriamento breve entre testes
        end
    end
end

println("Iniciando Varredura Automática no Puzzle #20...")
run_sweep()
println("\nVarredura concluída! Resultados em: $results_file")
