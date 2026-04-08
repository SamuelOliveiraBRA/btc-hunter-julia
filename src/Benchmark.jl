module BenchmarkModule

using ..ConfigModule: CFG
using ..UIModule: G, R, B, Y, M, C, W, DIM, X, BOLD, UL, 
                 clear, goto, hide_cursor, show_cursor, input, fmt_num, fmt_time, 
                 box_line, box_top, box_sep, box_bot, box_split, header
using ..ScannerOrchestrator
using ..BtcCrypto, ..MultiTarget, ..SecpOptimized
using Dates, Printf, CUDA

using ..GpuScanner
export run_benchmark, run_gpu_benchmark

"""
    run_gpu_benchmark()
Testa a performance bruta da GPU (CUDA).
"""
function run_gpu_benchmark()
    header("Benchmark de GPU (CUDA)")
    println("  $(W)Iniciando teste de estresse na placa de vídeo...$(X)")
    println("  $(DIM)Aguarde 10 segundos enquanto medimos a velocidade.$(X)\n")
    
    # Executa o medidor real do GpuScanner
    speed = GpuScanner.run_gpu_test(10)
    
    if speed < 0
        println("\n  $(R)$(BOLD)ERRO NO BENCHMARK!$(X)")
        if speed == -1.0
            println("  $(W)Motivo: Placa de vídeo incompatível ou CUDA não funcional.$(X)\n")
        else
            println("  $(W)Motivo: Falha ao compilar ou executar o kernel de teste.$(X)\n")
        end
    else
        println("\n  $(G)$(BOLD)TESTE CONCLUÍDO!$(X)")
        println("  $(W)Velocidade Média:$(X) $(G)$(fmt_num(speed))$(X) chaves/s")
        println("  $(DIM)Aproximadamente $(fmt_num(speed/1_000_000)) M/s$(X)\n")
    end
    
    input("  $(Y)Pressione ENTER para voltar...$(X) ")
end

"""
    measure_engine_speed(engine::Symbol, batch::Int, duration::Int)
Executa um teste de estresse real processando alvos reais (ECC + Hash160 + BloomFilter).
"""
function measure_engine_speed(engine::Symbol, batch::Int, duration::Int)
    # Alvo de teste real: pegamos dinamicamente do ranges.json (Puzzle 10)
    ranges_data = JSON.parsefile(joinpath(@__DIR__, "..", "data", "ranges.json"))["ranges"]
    test_addr = ranges_data[10]["endereco"]
    test_targets = MultiTarget.build_target_set([test_addr], BtcCrypto.base58_to_hash160)
    
    if engine == :gpu
        return GpuScanner.run_gpu_test(duration)
    end
    
    # Range de teste genérico
    start_k = BigInt(0x200)
    keys_done = Threads.Atomic{Int64}(0)
    stop = Ref(false)
    
    t_start = time()
    
    # Motor Julia (SecpOpt) - Carga de Trabalho Real
    if engine == :secp
        n_threads = CFG.cpus
        tasks = map(1:n_threads) do tid
            Threads.@spawn begin
                curr = start_k + BigInt(tid - 1)
                while !stop[]
                    # 1. Derivação ECC (Pesado)
                    pub = BtcCrypto.priv_to_pub_compressed(curr)
                    # 2. Hashing (Médio)
                    h160 = BtcCrypto.hash160(pub)
                    # 3. Verificação no Bloom Filter (Leve)
                    if MultiTarget.check_hit(test_targets, h160)
                        # Ignoramos o achado no benchmark, apenas contamos
                    end
                    
                    Threads.atomic_add!(keys_done, Int64(1))
                    curr += BigInt(n_threads)
                end
            end
        end
        
        sleep(duration)
        stop[] = true
        foreach(wait, tasks)
        
    # Motor BitCrack (CPU)
    elseif engine == :bitcrack
        # Mock para BitCrack se não estiver integrado nativamente como o Julia
        # (Idealmente chamamos o BitCrackEngine.check_batch aqui)
        # Se não houver BitCrack instalado, retorna 0
        try
            # Simulação via BitCrackEngine (se implementado)
            return 0.0 # Placeholder para bitcrack real
        catch
            return 0.0
        end
    end
    
    elapsed = time() - t_start
    return keys_done[] / elapsed
end

"""
    run_benchmark()
Testa a performance real de cada motor e sugere a melhor configuração.
"""
function run_benchmark()
    header("Benchmarking de Performance Real")
    println("  $(W)Iniciando testes de estresse no hardware...$(X)")
    println("  $(DIM)Cada motor será testado por 5 segundos.$(X)\n")
    
    results = []
    
    # Motores a testar
    target_engines = [:secp]
    if CUDA.functional(); push!(target_engines, :gpu); end
    
    for eng in target_engines
        println("  $(B)Testando Motor:$(X) $(lpad(string(eng), 8)) ...")
        
        # Medição real
        speed = measure_engine_speed(eng, CFG.batch_size, 5)
        
        push!(results, (engine=eng, speed=speed))
        println("  $(G)Resultado:$(X) $(fmt_num(speed)) chaves/s")
        println(box_sep())
    end
    
    # Tabela Final
    header("Resultado do Comparativo")
    sort!(results, by=x->x.speed, rev=true)
    
    for (i, r) in enumerate(results)
        medal = i == 1 ? "🥇" : i == 2 ? "🥈" : "🥉"
        println(box_line("  $medal $(rpad(string(r.engine), 10)) │ $(fmt_num(r.speed)) k/s"))
    end
    println(box_bot())
    
    if !isempty(results)
        best = results[1]
        println("\n  $(G)$(BOLD)MOTOR RECOMENDADO: $(uppercase(string(best.engine)))$(X)")
        op = input("  $(Y)Deseja aplicar como motor padrão?$(X) [S/n]: ")
        if lowercase(op) != "n"
            CFG.engine = best.engine
            if best.engine == :gpu; CFG.gpu = true; end
            println("  $(G)✓ Configuração salva!$(X)")
        end
    end
    sleep(2)
end

end # module
