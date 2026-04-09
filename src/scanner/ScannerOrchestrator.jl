module ScannerOrchestrator

using ..ConfigModule
using ..UIModule: G, R, B, Y, M, C, W, DIM, X, BOLD, UL, 
                 clear, goto, hide_cursor, show_cursor, input, fmt_num, fmt_time, progress_bar,
                 box_line, box_top, box_sep, box_bot, box_split, header, print_found_key
using ..BtcCrypto
using ..CheckpointManager
using ..MultiTarget
using ..BtcUtils
using ..Engines: BitCrackEngine, KeyhunterEngine, SecpEngine
using Base.Threads: @spawn, Atomic, atomic_add!
using Dates, Printf, Random, JSON

# Lê as configurações de range (incluindo pubkeys) diretamente do arquivo JSON.
# Isso garante que nenhuma configuração de carteira fique hardcoded no código.
_load_ranges_data() = JSON.parsefile(joinpath(@__DIR__, "..", "..", "data", "ranges.json"))["ranges"]

export scan_dashboard, run_worker_loop

"""
    scan_dashboard(...)
Lógica principal de orquestração e interface de progresso.
"""
function scan_dashboard(
    target_addrs::Vector{String},
    rng_min::BigInt, rng_max::BigInt,
    mode::Int,
    start_key::BigInt = rng_min,
    end_key::BigInt = (mode == 1 ? rng_max : mode == 2 ? rng_min : BigInt(0));
    puzzle_id::Int = 0
)
    # ── Validação de range ────────────────────────────────
    if mode == 1 && start_key == 0
        start_key = BigInt(1)
    end
    
    if mode == 1 && start_key > rng_max
        println("  $(R)⚠ Chave de início ($(string(start_key, base=16))) > máximo do puzzle. Abortando.$(X)")
        sleep(2); return
    end
    if mode == 2 && start_key < rng_min
        println("  $(R)⚠ Chave de início < mínimo do puzzle. Abortando.$(X)")
        sleep(2); return
    end

    # ── Multi-target setup ────────────────────────────────
    target_set = build_target_set(target_addrs, BtcCrypto.base58_to_hash160)
    
    # Para o motor GPU, tenta obter a chave pública do ranges.json (campo "pubkey").
    # Se disponível, substitui o alvo pelo X-coord da pubkey, permitindo comparação
    # direta e eficiente na GPU. NUNCA usa pubkey hardcoded no código.
    gpu_has_pubkey = false
    if CFG.engine == :gpu && puzzle_id > 0
        ranges_data = _load_ranges_data()
        if puzzle_id <= length(ranges_data)
            addr = isempty(target_addrs) ? ranges_data[puzzle_id]["endereco"] : target_addrs[1]
            gpu_has_pubkey = false # Strict compliance: no pubkeys fetched or utilized.
        end
    end
    n_targets  = target_count(target_set)

    rng_size   = rng_max - rng_min + 1
    mode_name  = mode == 1 ? "Sequencial →" : mode == 2 ? "← Reverso" : "⟳ Aleatório"
    batch_sz   = CFG.batch_size

    keys_done    = Atomic{Int64}(0)
    found_key    = Ref{BigInt}(BigInt(-1))
    found_addr   = Ref{String}("")
    last_key     = Ref{BigInt}(start_key)
    stop         = Ref(false)
    
    # ── JIT Warmup para GPU ──────────────────────────────
    if CFG.engine == :gpu
        header("Iniciando Busca...")
        println(box_top(" Inicializando Motor GPU "))
        println(box_line(" $(DIM)Compilando CUDA Kernel (JIT)... Aguarde$(X) "))
        println(box_bot())
        try
            KeyhunterEngine.gpu_scan_batch(target_set.hashes, [BigInt(1)], 8192)
            KeyhunterEngine.GPU_STATE[:d_points] = nothing
            KeyhunterEngine.GPU_STATE[:d_found] = nothing
            KeyhunterEngine.GPU_STATE[:last_range] = nothing
        catch
        end
    end

    session_start = time()
    base_elapsed  = 0.0
    spinner      = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    spin_idx     = Ref(1)

    # ── Header fixo ───────────────────────────────────────
    function print_fixed_header()
        header("Iniciando Busca...")
    end

    # ── Stats dinâmicos ───────────────────────────────────
    function render_stats(speed, elapsed, found=false)
        cur     = keys_done[]
        pct     = rng_size > 0 ? min(1.0, cur / Float64(rng_size)) : 0.0
        lk_str  = lpad(string(last_key[], base=16), 16, "0")
        eta     = speed > 0 && !found ? (Float64(rng_size) - cur) / speed : 0.0
        
        # Reposiciona o cursor e limpa linhas de estatísticas
        # (Isso depende de quantas linhas header() imprime)
        # Por simplicidade, daremos um "clear" se for a versão inicial
        # Mas para suavidade, usamos sequências ANSI
        
        if found
            fk_hex = lpad(string(found_key[], base=16), 64, "0")
            print("\r\033[K"); println(box_top("[+] SUCESSO! [+]"))
            print("\r\033[K"); println(box_line("$(G)$(BOLD)[OK] CHAVE ENCONTRADA!$(X)"))
            print("\r\033[K"); println(box_split(
                "$(W)Testadas$(X)  $(G)$(fmt_num(cur))$(X)",
                "$(W)Veloc.  $(X)  $(G)$(fmt_num(speed))$(X)/s"
            ))
            print("\r\033[K"); println(box_split(
                "$(W)Tempo   $(X)  $(Y)$(fmt_time(floor(BigInt, elapsed)))$(X)",
                "$(W)Privada $(X)  $(G)...$(fk_hex[end-12:end])$(X)"
            ))
            print("\r\033[K"); println(box_line("  Sessão finalizada com descoberta. "))
        else
            print("\r\033[K"); println(box_top("Estatísticas de Busca"))
            sp = spinner[spin_idx[]]
            spin_idx[] = mod1(spin_idx[] + 1, length(spinner))
            print("\r\033[K"); println(box_split(
                "$(W)Chave$(X)   $(C)0x$(lk_str)$(X)",
                "$(W)Tempo$(X)   $(Y)$(fmt_time(floor(BigInt, elapsed)))$(X)"
            ))
            print("\r\033[K"); println(box_split(
                "$(W)Testadas$(X)  $(G)$(fmt_num(cur))$(X)",
                "$(W)Veloc.$(X)   $(G)$(fmt_num(speed))$(X)/s  $(C)$sp$(X)"
            ))
            if mode != 3
                bar     = progress_bar(pct, 34)
                pct_str = @sprintf("%.2f%%", pct * 100)
                print("\r\033[K"); println(box_line("$(G)$(bar)$(X)  $(W)$(pct_str)$(X)"))
                eta_str = eta > 0 ? fmt_time(floor(BigInt, eta)) : "calculando..."
                print("\r\033[K"); println(box_line("$(DIM)ETA: $(eta_str)$(X)"))
            else
                print("\r\033[K"); println(box_line("$(DIM)Modo aleatório — progresso não linear$(X)"))
                print("\r\033[K"); println(box_line("$(DIM)$(fmt_num(cur)) chaves testadas$(X)"))
            end
        end

        print("\r\033[K"); println(box_sep())
        ckpt_note = (CFG.use_checkpoint && puzzle_id > 0 && mode != 3) ? "Checkpoint salvo │ " : ""
        print("\r\033[K"); println(box_line("$(DIM)$(ckpt_note)Ctrl+C para interromper  │  $(CFG.checkpoint_interval)s/update$(X)"))
        print("\r\033[K"); println(box_bot())
        flush(stdout)
    end

    print_fixed_header()
    render_stats(0.0, 0.0)

    # ── Thread de Monitoramento ───────────────────────────
    progress_task = @spawn begin
        last_cnt = 0; last_t = time(); last_ckpt_t = time()
        while !stop[]
            sleep(5.0)
            now_t = time()
            cur   = keys_done[]
            Δ     = cur - last_cnt; Δt = now_t - last_t
            speed = Δt > 0 ? Δ / Δt : 0.0
            total_elapsed = base_elapsed + (now_t - session_start)

            # Sobe 8 linhas para re-renderizar sem flicker (8 stats)
            print("\033[8A")
            render_stats(speed, total_elapsed)

            if CFG.use_checkpoint && puzzle_id > 0 && mode != 3
                if (now_t - last_ckpt_t) >= Float64(CFG.checkpoint_interval)
                    try
                        CheckpointManager.save_checkpoint(
                            puzzle_id, last_key[], cur, mode, total_elapsed)
                        last_ckpt_t = now_t
                    catch; end
                end
            end

            last_cnt = cur; last_t = now_t
        end
    end

    # ── Workers de busca ──────────────────────────────────
    # Verificação de compatibilidade GPU antes de lançar workers
    if CFG.engine == :gpu && !KeyhunterEngine.check_compatibility()
        CFG.engine = :bitcrack  # fallback para BitCrack quando GPU é incompatível
    end

    # Se usar GPU, limitamos a 1 worker de orquestração para não competir com o kernel
    n_threads     = CFG.engine == :gpu ? 1 : min(CFG.cpus, Threads.nthreads())
    safe_rng_max  = rng_max - BigInt(batch_sz * n_threads)

    # Pré-cálculo dos passos
    G_step           = SecpEngine.scalar_mul(BigInt(n_threads), SecpEngine.G_J)
    
    # Stride para o modo reverso (passo negativo)
    stride_val = mode == 2 ? -BigInt(batch_sz * n_threads) : BigInt(batch_sz * n_threads)
    G_batch_step     = SecpEngine.scalar_mul(stride_val, SecpEngine.G_J)
    G_batch_step_neg = SecpEngine.negate_point_jacobian(G_batch_step)

    worker_tasks = map(1:n_threads) do wid
        @spawn begin
            curr_base = if mode == 1
                if CFG.engine == :bitcrack
                    start_key + BigInt((wid - 1) * batch_sz)
                elseif CFG.engine == :gpu
                    start_key 
                else
                    start_key + BigInt(wid - 1)
                end
            elseif mode == 2
                if CFG.engine == :bitcrack
                    start_key - BigInt((wid - 1) * batch_sz)
                elseif CFG.engine == :gpu
                    start_key
                else
                    start_key - BigInt(wid - 1)
                end
            else
                r_safe = safe_rng_max > start_key ? safe_rng_max : rng_max
                BigInt(rand(start_key:r_safe))
            end

            if CFG.engine == :bitcrack
                # Motor BitCrackEngine (Multi-target nativo)
                # No modo reverso (2), inicializamos com o passo negativo
                stride_for_engine = mode == 2 ? -BigInt(batch_sz * n_threads) : BigInt(batch_sz * n_threads)
                state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, Int(stride_for_engine), CFG.both_formats)
                
                local_count = 0
                batch_counter = 0
                local_batch_idx = 0

                while !stop[]
                    res = BitCrackEngine.check_batch(state)
                    idx, h_f = res[1], res[2]
                    
                    if idx > 0
                        # Só agora fazemos a conta pesada de BigInt para registrar o achado
                        found_key[]  = curr_base + BigInt(local_batch_idx * (batch_sz * n_threads)) + BigInt(idx - 1)
                        found_addr[] = address_from_hash(target_set, h_f)
                        atomic_add!(keys_done, local_count)
                        stop[] = true; break
                    end
                    
                    local_count += batch_sz
                    batch_counter += 1
                    
                    if mode == 1 || mode == 2
                        current_pos = curr_base + BigInt(local_batch_idx * (batch_sz * n_threads))
                        if mode == 1 && current_pos > end_key; break; end
                        if mode == 2 && current_pos < end_key; break; end
                        
                        # Sincroniza progresso a cada 16 lotes (Suaviza a Velocidade na UI)
                        if mod(batch_counter, 16) == 0
                            atomic_add!(keys_done, local_count)
                            local_count = 0
                        end

                        # Sincroniza Chave/Checkpoint a cada 256 lotes (Reduz contenção de memória)
                        if batch_counter >= 256
                            last_key[] = current_pos 
                            batch_counter = 0
                        end

                        BitCrackEngine.next_batch!(state)
                        local_batch_idx += 1
                    else
                        # Modo Aleatório
                        stop[] && break
                        range_size = safe_rng_max > start_key ? safe_rng_max - start_key : BigInt(1)
                        curr_base = start_key + rand(BigInt(0):range_size)
                        state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, Int(stride_for_engine), CFG.both_formats)
                        local_batch_idx = 0
                        last_key[] = curr_base
                    end
                    yield()
                end
                atomic_add!(keys_done, local_count)
            elseif CFG.engine == :gpu
                # Motor GpuScanner (CUDA)
                gpu_batch = CFG.gpu_intensity * 1024
                
                while !stop[]
                    res_idx = KeyhunterEngine.gpu_scan_batch(target_set.hashes, [curr_base], gpu_batch)
                    
                    if res_idx == -1
                        break 
                    elseif res_idx > 0
                        found_key[]  = curr_base + BigInt(res_idx - 1)
                        actual_scanned = KeyhunterEngine.GPU_STATE[:last_batch]
                        atomic_add!(keys_done, max(Int64(actual_scanned), Int64(res_idx)))
                        h_found = BtcCrypto.hash160(BtcCrypto.priv_to_pub_compressed(found_key[]))
                        found_addr[] = address_from_hash(target_set, h_found)
                        stop[] = true; break
                    end
                    
                    actual_scanned = KeyhunterEngine.GPU_STATE[:last_batch]
                    atomic_add!(keys_done, actual_scanned)
                    
                    if mode == 1 # Sequencial
                        curr_base += BigInt(actual_scanned)
                        curr_base > end_key && break
                    elseif mode == 2 # Reverso
                        curr_base -= BigInt(actual_scanned)
                        curr_base < end_key && break
                    end
                    
                    last_key[] = curr_base
                    stop[] && break
                    
                    if mode == 3 # Aleatório
                        curr_base = BigInt(rand(start_key:rng_max))
                        last_key[] = curr_base
                    end
                    yield()
                end
            else
                # Motor SecpEngine (padrão)
                P_base = SecpEngine.scalar_mul(curr_base, SecpEngine.G_J)
                batch_points = Vector{SecpEngine.PointJacobian}(undef, batch_sz)

                while !stop[]
                    P_temp = P_base
                    for i in 1:batch_sz
                        batch_points[i] = P_temp
                        P_temp = SecpEngine.add_points_jacobian(P_temp, G_step)
                    end

                    affine_pts = SecpEngine.batch_normalize(batch_points)
                    pubs_comp = BtcCrypto.serialize_compressed_batch(affine_pts)

                    for i in 1:batch_sz
                        h160_c = BtcCrypto.hash160(pubs_comp[i])
                        if check_hit(target_set, h160_c)
                            found_key[]  = curr_base + BigInt((i - 1) * n_threads)
                            found_addr[] = address_from_hash(target_set, h160_c)
                            stop[] = true; break
                        end
                        if CFG.both_formats
                            pub_uncomp = BtcCrypto.serialize_uncompressed_batch([affine_pts[i]])[1]
                            h160_u = BtcCrypto.hash160(pub_uncomp)
                            if check_hit(target_set, h160_u)
                                found_key[]  = curr_base + BigInt((i - 1) * n_threads)
                                found_addr[] = address_from_hash(target_set, h160_u)
                                stop[] = true; break
                            end
                        end
                    end
                    stop[] && break

                    atomic_add!(keys_done, batch_sz)
                    if mode == 1
                        curr_base += BigInt(batch_sz * n_threads)
                        curr_base > end_key && break
                        P_base = SecpEngine.add_points_jacobian(P_base, G_batch_step)
                    elseif mode == 2
                        curr_base -= BigInt(batch_sz * n_threads)
                        curr_base < end_key && break
                        P_base = SecpEngine.add_points_jacobian(P_base, G_batch_step_neg)
                    else
                        curr_base = BigInt(rand(start_key:rng_max))
                        P_base = SecpEngine.scalar_mul(curr_base, SecpEngine.G_J)
                    end
                    last_key[] = curr_base
                    yield()
                end
            end
        end
    end

    foreach(wait, worker_tasks)
    stop[] = true
    wait(progress_task)

    # ── Finalização ───────────────────────────────────────
    total_elapsed = base_elapsed + (time() - session_start)
    final  = keys_done[]
    speed  = total_elapsed > 0 ? final / total_elapsed : 0.0

    if found_key[] >= 0
        print("\033[8A\r\033[J") 
        render_stats(speed, total_elapsed, true)
        pk     = found_key[]
        pk_hex = lpad(string(pk, base=16), 64, "0")
        wif    = BtcUtils.generate_wif(pk)
        pub_hex = bytes2hex(BtcCrypto.priv_to_pub_compressed(pk))
        addr   = found_addr[]

        print_found_key(addr, pub_hex, pk_hex, wif)
        BtcUtils.save_found_key(puzzle_id, addr, pub_hex, pk_hex, wif)
        puzzle_id > 0 && CheckpointManager.delete_checkpoint(puzzle_id)
    else
        print("\033[8A\r\033[J") 
        render_stats(speed, total_elapsed)
        println(box_top(" SESSÃO CONCLUÍDA "))
        println(box_line(" Chave não encontrada no intervalo. "))
        println(box_bot())
    end

    show_cursor()
    println("\n  Pressione ENTER para voltar ao menu...")
    readline()
end

end # module
