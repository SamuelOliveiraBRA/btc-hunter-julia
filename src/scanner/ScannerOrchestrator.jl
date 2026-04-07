module ScannerOrchestrator

using ..ConfigModule
using ..UIModule: G, R, B, Y, M, C, W, DIM, X, BOLD, UL, 
                 clear, goto, hide_cursor, show_cursor, input, fmt_num, fmt_time, progress_bar,
                 box_line, box_top, box_sep, box_bot, box_split, header
using ..BtcCrypto
using ..BitCrackEngine
using ..SecpOptimized
using ..CheckpointManager
using ..MultiTarget
using ..BtcUtils
using ..GpuCrypto
using ..GpuScanner
using Base.Threads: @spawn, Atomic, atomic_add!
using Dates, Printf, Random, JSON, HTTP

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
    n_targets  = target_count(target_set)

    rng_size   = rng_max - rng_min + 1
    mode_name  = mode == 1 ? "Sequencial →" : mode == 2 ? "← Reverso" : "⟳ Aleatório"
    batch_sz   = CFG.batch_size

    keys_done    = Atomic{Int64}(0)
    found_key    = Ref{BigInt}(BigInt(-1))
    found_addr   = Ref{String}("")
    last_key     = Ref{BigInt}(start_key)
    stop         = Ref(false)
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
            println(box_top("⭐ SUCESSO! ⭐"))
            println(box_line("$(G)$(BOLD)✅ CHAVE ENCONTRADA!$(X)"))
            println(box_line("$(W)Privada$(X)  $(G)...$(fk_hex[end-15:end])$(X)"))
        else
            println(box_top("Estatísticas de Busca"))
            sp = spinner[spin_idx[]]
            spin_idx[] = mod1(spin_idx[] + 1, length(spinner))
            println(box_split(
                "$(W)Chave$(X)   $(C)0x$(lk_str)$(X)",
                "$(W)Tempo$(X)   $(Y)$(fmt_time(floor(BigInt, elapsed)))$(X)"
            ))
            println(box_split(
                "$(W)Testadas$(X)  $(G)$(fmt_num(cur))$(X)",
                "$(W)Veloc.$(X)   $(G)$(fmt_num(speed))$(X)/s  $(C)$sp$(X)"
            ))
            if mode != 3
                bar     = progress_bar(pct, 34)
                pct_str = @sprintf("%.2f%%", pct * 100)
                println(box_line("$(G)$(bar)$(X)  $(W)$(pct_str)$(X)"))
                eta_str = eta > 0 ? fmt_time(floor(BigInt, eta)) : "calculando..."
                println(box_line("$(DIM)ETA: $(eta_str)$(X)"))
            else
                println(box_line("$(DIM)Modo aleatório — progresso não linear$(X)"))
                println(box_line("$(DIM)$(fmt_num(cur)) chaves testadas$(X)"))
            end
        end

        println(box_sep())
        ckpt_note = (CFG.use_checkpoint && puzzle_id > 0 && mode != 3) ? "Checkpoint salvo │ " : ""
        println(box_line("$(DIM)$(ckpt_note)Ctrl+C para interromper  │  5s/update$(X)"))
        println(box_bot())
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

            # Sobe 8 linhas para re-renderizar sem flicker (1 top + 7 stats)
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
    n_threads = CFG.cpus
    safe_rng_max = rng_max - BigInt(batch_sz * n_threads)

    # Pré-cálculo dos passos
    G_step           = SecpOptimized.scalar_mul(BigInt(n_threads), SecpOptimized.G_J)
    G_batch_step     = SecpOptimized.scalar_mul(BigInt(batch_sz * n_threads), SecpOptimized.G_J)
    G_batch_step_neg = SecpOptimized.negate_point_jacobian(G_batch_step)

    worker_tasks = map(1:n_threads) do wid
        @spawn begin
            curr_base = if mode == 1
                CFG.engine == :bitcrack ? start_key + BigInt((wid - 1) * batch_sz) : start_key + BigInt(wid - 1)
            elseif mode == 2
                CFG.engine == :bitcrack ? start_key - BigInt((wid - 1) * batch_sz) : start_key - BigInt(wid - 1)
            else
                r_safe = safe_rng_max > start_key ? safe_rng_max : rng_max
                BigInt(rand(start_key:r_safe))
            end

            if CFG.engine == :bitcrack
                # Motor BitCrackEngine (Multi-target nativo)
                state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, batch_sz * n_threads, CFG.both_formats)

                while !stop[]
                    idx, h_f = BitCrackEngine.check_batch(state)
                    if idx > 0
                        found_key[]  = curr_base + BigInt(idx - 1)
                        found_addr[] = address_from_hash(target_set, h_f)
                        stop[] = true; break
                    end
                    atomic_add!(keys_done, batch_sz)
                    if mode == 1
                        curr_base += BigInt(batch_sz * n_threads)
                        curr_base > end_key && (stop[] = true; break)
                        BitCrackEngine.next_batch!(state)
                    elseif mode == 2
                        curr_base -= BigInt(batch_sz * n_threads)
                        curr_base < end_key && (stop[] = true; break)
                        state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, batch_sz * n_threads, CFG.both_formats)
                    else
                        curr_base = BigInt(rand(start_key:rng_max))
                        state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, batch_sz * n_threads, CFG.both_formats)
                    end
                    last_key[] = curr_base
                    yield()
                end
            else
                # Motor SecpOptimized (padrão)
                P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
                batch_points = Vector{SecpOptimized.PointJacobian}(undef, batch_sz)

                while !stop[]
                    P_temp = P_base
                    for i in 1:batch_sz
                        batch_points[i] = P_temp
                        P_temp = SecpOptimized.add_points_jacobian(P_temp, G_step)
                    end

                    affine_pts = SecpOptimized.batch_normalize(batch_points)
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
                        curr_base > end_key && (stop[] = true; break)
                        P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step)
                    elseif mode == 2
                        curr_base -= BigInt(batch_sz * n_threads)
                        curr_base < end_key && (stop[] = true; break)
                        P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step_neg)
                    else
                        curr_base = BigInt(rand(start_key:rng_max))
                        P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
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
        pk     = found_key[]
        pk_hex = lpad(string(pk, base=16), 64, "0")
        wif    = BtcUtils.generate_wif(pk)
        pub_hex = bytes2hex(BtcCrypto.priv_to_pub_compressed(pk))
        addr   = found_addr[]

        render_stats(speed, total_elapsed, true)
        println("  $(G)$(BOLD)Endereço$(X) : $(Y)$(addr)$(X)")
        println("  $(G)$(BOLD)Privada$(X)  : $(Y)$(pk_hex)$(X)")
        println("  $(G)$(BOLD)WIF$(X)      : $(Y)$(wif)$(X)")
        # println("  $(G)$(BOLD)Pública$(X)  : $(Y)$(pub_hex)$(X)")
        
        # Salva resultado
        mkpath("outputs")
        open("outputs/encontradas.txt", "a") do f
            println(f, "[$(now())] Puzzle #$puzzle_id Found!")
            println(f, "Addr: $addr\nPriv: $pk_hex\nWIF: $wif\n")
        end
        puzzle_id > 0 && CheckpointManager.delete_checkpoint(puzzle_id)
    else
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
