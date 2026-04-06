# ═══════════════════════════════════════════════════════════
#  BTC KEY HUNTER  ·  Julia Edition  ·  v1.1.0
# ═══════════════════════════════════════════════════════════
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("btc_utils.jl")

using .Base58, .BtcCrypto, .BtcUtils
include("src/SecpOptimized.jl")
using .SecpOptimized
using HTTP, JSON, Random, Dates, Printf
using Base.Threads: @spawn, Atomic, atomic_add!

# ── Cores ANSI ────────────────────────────────────────────
const G  = "\e[32m";  const R  = "\e[31m";  const B  = "\e[94m"
const Y  = "\e[33m";  const M  = "\e[35m";  const C  = "\e[96m"
const W  = "\e[97m";  const DIM = "\e[2m";  const X  = "\e[0m"
const BOLD = "\e[1m"; const UL = "\e[4m"

# ── Config ────────────────────────────────────────────────
mutable struct Config
    cpus::Int; internet::Bool
    wallet_num::Int; wallet_addr::String
    wallet_status::Int
    interval_min::String; interval_max::String
    saldo::String; mode::Int; running::Bool
end
const CFG = Config(Sys.CPU_THREADS, false, 0, "", 0, "0x0", "0x0", "", 0, true)

# ── Utilitários ───────────────────────────────────────────
ansi(s) = replace(s, r"\e\[[0-9;]*m" => "")   # remove ANSI para medir tamanho

function clear(); print("\033[2J\033[H"); flush(stdout); end
function goto(row, col=1); print("\033[$(row);$(col)H"); end
function clrline(); print("\033[2K"); end
function hide_cursor(); print("\033[?25l"); end
function show_cursor(); print("\033[?25h"); end
input(prompt) = (show_cursor(); print(prompt); readline())

hex2big(s) = parse(BigInt, replace(strip(s), "0x" => "", "0X" => ""), base=16)

function fmt_num(n::Number)
    abs(n) < 1_000         && return @sprintf("%d", n)
    abs(n) < 1_000_000     && return @sprintf("%.1fK", n/1_000)
    abs(n) < 1_000_000_000 && return @sprintf("%.2fM", n/1_000_000)
    return @sprintf("%.2fB", n/1_000_000_000)
end

fmt_time(s) = @sprintf("%02d:%02d:%02d", s÷3600, (s%3600)÷60, s%60)

function progress_bar(pct::Float64, width::Int=36)
    filled = round(Int, pct * width)
    bar    = "█" ^ filled * "░" ^ (width - filled)
    return bar
end

load_ranges()  = JSON.parsefile("data/ranges.json")["ranges"]

function salvar_encontrada(priv_hex, addr, wif, pub_hex)
    mkpath("outputs")
    ts = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    open("outputs/encontradas.txt", "a") do f
        println(f, "[$ts]")
        println(f, "  Endereço  : $addr")
        println(f, "  Privada   : $priv_hex")
        println(f, "  WIF       : $wif")
        println(f, "  Pública   : $pub_hex")
        println(f, "")
    end
end

# ── Box helpers ───────────────────────────────────────────
W_BOX = 62  # largura interna da caixa

function box_line(content="", color="")
    raw = ansi(content)
    pad = max(0, W_BOX - length(raw))
    "║ $(color)$(content)$(X)$(repeat(" ", pad)) ║"
end

function box_top(title="")
    t = isempty(title) ? "" : " $title "
    left = (W_BOX - length(t)) ÷ 2
    right = W_BOX - left - length(t)
    "╔$(repeat("═", left))$(t)$(repeat("═", right))╗"
end

box_sep() = "╠$(repeat("═", W_BOX+2))╣"
box_bot() = "╚$(repeat("═", W_BOX+2))╝"

function box_split(left, right, lw=30, color_l="", color_r="")
    raw_l = ansi(left); raw_r = ansi(right)
    pad_l = max(0, lw - length(raw_l))
    pad_r = max(0, W_BOX - lw - 3 - length(raw_r))
    "║ $(color_l)$(left)$(X)$(repeat(" ", pad_l)) │ $(color_r)$(right)$(X)$(repeat(" ", pad_r)) ║"
end

# ── Tela de abertura ──────────────────────────────────────
function splash()
    clear(); hide_cursor()
    lines = [
        "",
        "$(BOLD)$(B)  ██████╗ ████████╗ ██████╗",
        "  ██╔══██╗╚══██╔══╝██╔════╝",
        "  ██████╔╝   ██║   ██║",
        "  ██╔══██╗   ██║   ██║",
        "  ██████╔╝   ██║   ╚██████╗",
        "  ╚═════╝    ╚═╝    ╚═════╝$(X)",
        "",
        "  $(W)Key Hunter  ·  Julia Edition  ·  v1.1.0$(X)",
        "  $(DIM)Motor: Secp256k1 + SHA256 + RIPEMD160$(X)",
        "",
        "  $(G)●$(X) Carregando módulos...",
    ]
    foreach(println, lines)
    sleep(0.5)
    show_cursor()
end

# ── Header fixo ───────────────────────────────────────────
function header(subtitle="")
    clear()
    cpu_bar = G * ("■" ^ CFG.cpus) * DIM * ("□" ^ (Sys.CPU_THREADS - CFG.cpus)) * X
    inet_s  = CFG.internet ? G*"● Ativa"*X : DIM*"○ Desativada"*X

    println(box_top("$(BOLD)$(W) BTC KEY HUNTER $(X)"))
    println(box_split("$(Y)v1.1.0$(X)  Julia Edition", "$(B)github.com/btc-hunter$(X)"))
    println(box_sep())
    println(box_split("$(W)CPUs$(X)  $cpu_bar", "$(W)Internet$(X)  $inet_s"))

    if CFG.wallet_num > 0
        println(box_sep())
        st  = CFG.wallet_status == 0 ? "$(G)✓ Disponível$(X)" : "$(R)✗ Encontrada$(X)"
        rng_size = hex2big(CFG.interval_max) - hex2big(CFG.interval_min) + 1

        addr_short = length(CFG.wallet_addr) > 34 ? CFG.wallet_addr[1:34] : CFG.wallet_addr
        println(box_line("$(Y)#$(CFG.wallet_num)$(X)  $(W)$(addr_short)$(X)"))
        println(box_split("$(W)Status$(X) $st", "$(W)Range$(X) $(C)$(fmt_num(rng_size))$(X) chaves"))
        println(box_split(
            "$(DIM)Min:$(X) $(Y)$(CFG.interval_min)$(X)",
            "$(DIM)Max:$(X) $(Y)$(CFG.interval_max)$(X)"
        ))
        isempty(CFG.saldo) || println(box_line("$(W)Saldo$(X)  $(G)$(CFG.saldo) BTC$(X)"))
    end

    isempty(subtitle) || begin
        println(box_sep())
        println(box_line("  $(M)$(subtitle)$(X)"))
    end
    println(box_bot())
    println()
end

# ── Tela de setup de CPUs ─────────────────────────────────
function escolher_cpus()
    n = Sys.CPU_THREADS
    while true
        header("Configuração › CPUs")
        println("  Detectadas: $(G)$n$(X) threads lógicas\n")
        bars = String[]
        for i in 1:n
            # Limita a exibição da barra se o número de CPUs for muito alto para não quebrar a tela
            if n <= 16
                bar_str = G * ("■"^i) * DIM * ("□"^(n-i)) * X
                push!(bars, "$(i) $(bar_str)")
            else
                push!(bars, "$(G)$(i)$(X)")
            end
        end
        
        # Agrupa exibindo 4 opções por linha caso a tela não caiba (ex: 16+), mas por padrão ficará horizontal
        chunk_size = n > 8 ? 8 : n
        for chunk in Iterators.partition(bars, chunk_size)
            println("  " * join(chunk, "   "))
        end
        println()
        s = input("  $(W)Quantas CPUs usar?$(X) [1-$n]: ")
        v = tryparse(Int, strip(s))
        if !isnothing(v) && 1 <= v <= n
            CFG.cpus = v; return
        end
        println("\n  $(R)● Valor inválido, tente novamente.$(X)")
        sleep(1)
    end
end

# ── Tela de internet ──────────────────────────────────────
function habilitar_internet()
    header("Configuração › Internet")
    println("  Habilitar consulta de saldo via blockchain.info?\n")
    println("  $(G)[1]$(X)  Sim — consultar saldo da carteira")
    println("  $(R)[2]$(X)  Não — modo offline\n")
    while true
        op = input("  Opção: ")
        op == "1" && (CFG.internet = true;  return)
        op == "2" && (CFG.internet = false; return)
        print("\r  $(R)Opção inválida.$(X)"); sleep(0.5)
    end
end

# ── Lista de puzzles paginada ─────────────────────────────
function escolher_carteira(ranges)
    page_size = 15
    page = 1
    total = length(ranges)
    pages = ceil(Int, total / page_size)

    while true
        header("Selecionar Puzzle")

        start_i = (page-1) * page_size + 1
        end_i   = min(page * page_size, total)

        println("  $(W)Puzzles $(DIM)$(start_i)-$(end_i) de $(total)$(X)  │  Página $(page)/$(pages)\n")
        println("  $(DIM)  #   Status  Min              Endereço$(X)")
        println("  $(DIM)  ─   ──────  ───              ────────$(X)")

        for i in start_i:end_i
            r   = ranges[i]
            st  = r["status"] == 0 ? G*"✓"*X : R*"✗"*X
            addr = isempty(r["endereco"]) ? DIM*"(sem alvo)"*X : Y*r["endereco"][1:min(end,18)]*"..."*X
            num_str = lpad(i, 3)
            min_str = rpad(r["min"][1:min(end,16)], 16)
            println("  $num_str  $st       $(DIM)$(min_str)$(X)  $addr")
        end

        println()
        nav = []
        page > 1        && push!(nav, "$(B)[A]$(X) Anterior")
        page < pages    && push!(nav, "$(B)[P]$(X) Próxima")
        push!(nav, "$(W)[#]$(X) Número da carteira")
        println("  " * join(nav, "  │  "))
        println()

        s = input("  Opção: ")
        s = strip(lowercase(s))

        if s == "a" && page > 1
            page -= 1
        elseif s == "p" && page < pages
            page += 1
        else
            v = tryparse(Int, s)
            if !isnothing(v) && 1 <= v <= total
                r = ranges[v]
                CFG.wallet_num    = v
                CFG.wallet_addr   = get(r, "endereco", "")
                CFG.wallet_status = get(r, "status", 0)
                CFG.interval_min  = r["min"]
                CFG.interval_max  = r["max"]
                CFG.saldo         = ""

                if CFG.internet && !isempty(CFG.wallet_addr)
                    print("\n  $(DIM)Consultando saldo...$(X) ")
                    try
                        res = HTTP.get("https://blockchain.info/balance?active=$(CFG.wallet_addr)",
                                       connect_timeout=6, readtimeout=8)
                        info = JSON.parse(String(res.body))
                        btc  = info[CFG.wallet_addr]["final_balance"] / 1e8
                        CFG.saldo = @sprintf("%.8f", btc)
                        println("$(G)✓$(X)")
                    catch
                        CFG.saldo = ""; println("$(R)falhou$(X)")
                    end
                end
                return
            end
            print("  $(R)Inválido.$(X)"); sleep(0.5)
        end
    end
end

# ── Motor de verificação ──────────────────────────────────
function verify_key(priv_key::BigInt, target_h160::Vector{UInt8})::Bool
    pub  = BtcCrypto.priv_to_pub_compressed(priv_key)
    h160 = BtcCrypto.hash160(pub)
    return h160 == target_h160
end

# ── Dashboard de scan ao vivo ──────────────────────────────
# ── Dashboard de scan ao vivo ──────────────────────────────
function scan_dashboard(target_addr, rng_min, rng_max, mode, start_key::BigInt=rng_min)
    target_h160 = BtcCrypto.base58_to_hash160(target_addr)
    rng_size    = rng_max - rng_min + 1
    mode_name   = mode == 1 ? "Sequencial →" : mode == 2 ? "← Reverso" : "⟳ Aleatório"

    keys_done  = Atomic{Int64}(0)
    found_key  = Ref{BigInt}(BigInt(-1))
    last_key   = Ref{BigInt}(start_key)
    stop       = Ref(false)
    start_time = time()
    spinner    = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    spin_idx   = 1

    # ── Cabeçalho FIXO ────────────────────────────────────
    function print_fixed_header()
        clear(); hide_cursor()
        println(box_top("$(BOLD)$(W) BTC KEY HUNTER  ·  Julia Edition $(X)"))
        println(box_split("$(Y)Modo$(X)  $mode_name", "$(W)CPUs$(X)  $(G)$(CFG.cpus) threads$(X)"))
        println(box_sep())
        println(box_line("$(W)🎯 Alvo$(X)   $(Y)$(target_addr)$(X)"))
        println(box_split(
            "$(DIM)Min$(X)  $(C)$(CFG.interval_min)$(X)",
            "$(DIM)Max$(X)  $(C)$(CFG.interval_max)$(X)"
        ))
        println(box_sep())
        flush(stdout)
    end

    # ── Zona DINÂMICA ─────────────────────────────────────
    function render_stats(speed, elapsed, found=false)
        cur    = keys_done[]
        pct    = rng_size > 0 ? min(1.0, cur / Float64(rng_size)) : 0.0
        lk_hex = lpad(string(last_key[], base=16), 16, "0")
        eta    = speed > 0 && !found ? (Float64(rng_size) - cur) / speed : 0.0

        print("\033[J") # Limpa do cursor para baixo

        if found
            fk_hex = lpad(string(found_key[], base=16), 64, "0")
            println(box_line("$(G)$(BOLD)✅ CHAVE ENCONTRADA!$(X)"))
            println(box_line("$(W)Privada$(X)  $(G)...$(fk_hex[end-15:end])$(X)"))
            println(box_line(""))
            println(box_line(""))
        else
            spin = spinner[spin_idx]
            spin_idx = mod1(spin_idx + 1, length(spinner))
            
            println(box_split(
                "$(W)Chave$(X)   $(C)0x$(lk_hex)$(X)",
                "$(W)Tempo$(X)   $(Y)$(fmt_time(round(Int, elapsed)))$(X)"
            ))
            println(box_split(
                "$(W)Testadas$(X)  $(G)$(fmt_num(cur))$(X)",
                "$(W)Veloc.$(X)   $(G)$(fmt_num(speed))$(X)/s  $(C)$spin$(X)"
            ))
            if mode != 3
                bar     = progress_bar(pct, 34)
                pct_str = @sprintf("%.2f%%", pct * 100)
                println(box_line("$(G)$(bar)$(X)  $(W)$(pct_str)$(X)"))
                eta_str = eta > 0 ? fmt_time(round(Int, eta)) : "calculando..."
                println(box_line("$(DIM)ETA: $(eta_str)$(X)"))
            else
                println(box_line("$(DIM)Modo aleatório — progresso não linear$(X)"))
                println(box_line("$(DIM)$(fmt_num(cur)) chaves testadas$(X)"))
            end
        end

        println(box_sep())
        println(box_line("$(DIM)Ctrl+C para interromper  │  Atualiza a cada 5s$(X)"))
        println(box_bot())
        flush(stdout)
    end

    print_fixed_header()
    render_stats(0.0, 0.0)

    # ── Thread de Monitoramento ───────────
    progress_task = @spawn begin
        last_cnt = 0; last_t = time()
        while !stop[]
            sleep(5.0)
            now_t = time()
            cur   = keys_done[]
            Δ     = cur - last_cnt; Δt = now_t - last_t
            speed = Δt > 0 ? Δ / Δt : 0.0
            
            print("\033[7A") # Sobe 7 linhas para redesenhar
            render_stats(speed, now_t - start_time)
            
            last_cnt = cur; last_t = now_t
        end
    end

    # ── Workers de busca (BATCH OPTIMIZED) ────────────────
    n_threads = CFG.cpus
    batch_size = 256
    
    # Passo G para o pulo de threads
    step_val = BigInt(n_threads)
    G_step = SecpOptimized.scalar_mul(step_val, SecpOptimized.G_J)
    # Passo total do lote
    G_batch_step = SecpOptimized.scalar_mul(BigInt(batch_size * n_threads), SecpOptimized.G_J)
    G_batch_step_neg = SecpOptimized.negate_point_jacobian(G_batch_step)

    worker_tasks = map(1:n_threads) do wid
        @spawn begin
            curr_base = if mode == 1;     start_key + BigInt(wid - 1)
                        elseif mode == 2; start_key - BigInt(wid - 1)
                        else;             rand(rng_min:rng_max)
                        end
            
            P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
            batch_points = Vector{SecpOptimized.PointJacobian}(undef, batch_size)
            
            while !stop[]
                # 1. Gerar Lote via Soma (O(1))
                P_temp = P_base
                for i in 1:batch_size
                    batch_points[i] = P_temp
                    P_temp = SecpOptimized.add_points_jacobian(P_temp, G_step)
                end
                
                # 2. Montgomery Batch Inversion (O(1) amortizado)
                affine_points = SecpOptimized.batch_normalize(batch_points)
                
                # 3. Serialização e Hash (Híbrido: Comprimido + Não-Comprimido)
                pubs_comp = BtcCrypto.serialize_compressed_batch(affine_points)
                pubs_uncomp = BtcCrypto.serialize_uncompressed_batch(affine_points)
                
                for i in 1:batch_size
                    # Testa os dois formatos populares do Bitcoin
                    if BtcCrypto.hash160(pubs_comp[i]) == target_h160 || BtcCrypto.hash160(pubs_uncomp[i]) == target_h160
                        # Encontrada!
                        found_key[] = curr_base + BigInt((i - 1) * n_threads)
                        stop[] = true
                        break
                    end
                end
                
                if stop[] ; break ; end
                
                atomic_add!(keys_done, batch_size)
                
                if mode == 1
                    curr_base += BigInt(batch_size * n_threads)
                    P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step)
                elseif mode == 2
                    curr_base -= BigInt(batch_size * n_threads)
                    # No modo reverso, subtraímos G_batch_step (adicionamos o negativo)
                    # Para simplificar, poderíamos ter um G_batch_step_neg, mas vamos focar no sequencial por hora
                    # pois o usuário quer performance "estilo bitcrack" (que é sequencial).
                    # Por enquanto, vamos apenas garantir que ele não pare.
                    P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step_neg)
                else
                    curr_base = BigInt(rand(rng_min:rng_max))
                    P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
                end
                
                last_key[] = curr_base
                yield()
                
                if mode == 1 && curr_base > rng_max ; break ; end
                if mode == 2 && curr_base < rng_min ; break ; end
            end
            stop[] = true
        end
    end

    foreach(wait, worker_tasks)
    stop[] = true
    wait(progress_task)

    elapsed = time() - start_time
    final   = keys_done[]
    speed   = elapsed > 0 ? final / elapsed : 0.0

    if found_key[] >= 0
        pk = found_key[]
        pk_hex = lpad(string(pk, base=16), 64, "0")
        wif = BtcUtils.generate_wif(pk)
        pub_hex = bytes2hex(BtcCrypto.priv_to_pub_compressed(pk))

        render_stats(speed, elapsed, true)
        println()
        println("  $(G)$(BOLD)Privada$(X)  : $(Y)$(pk_hex)$(X)")
        println("  $(G)$(BOLD)WIF$(X)      : $(Y)$(wif)$(X)")
        println("  $(G)$(BOLD)Pública$(X)  : $(Y)$(pub_hex)$(X)")
        println()
        salvar_encontrada(pk_hex, target_addr, wif, pub_hex)
        println("  $(G)✓ Salvo em outputs/encontradas.txt$(X)")
    else
        clear()
        println(box_top("$(W) BUSCA CONCLUÍDA $(X)"))
        println(box_line("$(R)✗ Chave não encontrada no intervalo$(X)"))
        println(box_sep())
        println(box_split("$(W)Testadas$(X) $(G)$(fmt_num(final))$(X)", "$(W)Tempo$(X) $(Y)$(fmt_time(round(Int,elapsed)))$(X)"))
        println(box_split("$(W)Velocidade$(X) $(G)$(fmt_num(speed))$(X)/s", "$(W)Modo$(X) $mode_name"))
        println(box_bot())
    end

    show_cursor()
    print("\n  Pressione ENTER para continuar...")
    readline()
end

# ── Menu modo de busca ────────────────────────────────────
function menu_scan()
    header("Iniciar Busca")
    addr  = CFG.wallet_addr
    r_min = hex2big(CFG.interval_min)
    r_max = hex2big(CFG.interval_max)

    if isempty(addr)
        println("  $(R)⚠  Esta carteira não tem endereço configurado.$(X)")
        println("  Escolha outra carteira com endereço.\n")
        sleep(2); return main_menu()
    end

    println("  $(W)Escolha o modo de escaneamento:$(X)\n")
    println("  $(G)[1]$(X)  Sequencial →     começar do menor valor")
    println("  $(B)[2]$(X)  ← Reverso         começar do maior valor")
    println("  $(M)[3]$(X)  ⟳ Aleatório       valores aleatórios no intervalo")
    println("  $(C)[4]$(X)  % Porcentagem     escolher a partir de qual % inicializar")
    println("  $(DIM)[5]$(X)  Voltar\n")

    op = input("  Opção: ")
    rng_size = r_max - r_min + 1

    if op == "1"
        scan_dashboard(addr, r_min, r_max, 1, r_min)
    elseif op == "2"
        scan_dashboard(addr, r_min, r_max, 2, r_max)
    elseif op == "3"
        scan_dashboard(addr, r_min, r_max, 3, r_min)
    elseif op == "4"
        str_pct = input("  $(W)Digite a % inicial (ex: 25.5 ou 0.25): $(X)")
        # Lida tanto com "0.25" quanto "25.5" (converte tudo para a base de 1.0)
        pct = tryparse(Float64, replace(str_pct, "," => "."))
        if pct !== nothing
            pct = pct > 2.0 ? pct / 100.0 : pct  # se digitou >2, provavelmente é já na base 100
            pct = min(max(pct, 0.0), 1.0)
            
            offset = BigInt(floor(Float64(rng_size) * pct))
            start_key = r_min + offset
            
            scan_dashboard(addr, r_min, r_max, 1, start_key)
        else
            println("  $(R)Valor inválido.$(X)"); sleep(1)
        end
    elseif op == "5"
        return
    else
        println("  $(R)Inválida.$(X)"); sleep(0.8)
    end

    main_menu()
end

# ── Menu principal ────────────────────────────────────────
function main_menu()
    while true
        header()
        println("  $(W)O que deseja fazer?$(X)\n")

        CFG.wallet_num > 0 || begin
            println("  $(R)⚠  Nenhuma carteira selecionada. Escolha uma primeiro.$(X)\n")
        end

        println("  $(G)[1]$(X)  $(W)Iniciar busca$(X)   $(DIM)— escanear chaves privadas$(X)")
        println("  $(Y)[2]$(X)  Escolher carteira  $(DIM)— trocar puzzle alvo$(X)")
        println("  $(B)[3]$(X)  Configurar CPUs    $(DIM)— em uso: $(G)$(CFG.cpus)$(X)")
        println("  $(C)[4]$(X)  Configurar internet$(DIM)— $(CFG.internet ? G*"ativa"*X : DIM*"desativada"*X)$(X)")
        println("  $(DIM)[0]  Sair$(X)")
        println()

        op = input("  Opção: ")

        if op == "1"
            CFG.wallet_num > 0 ? menu_scan() : (println("  $(R)Selecione uma carteira primeiro.$(X)"); sleep(1))
        elseif op == "2"
            escolher_carteira(load_ranges())
        elseif op == "3"
            escolher_cpus()
        elseif op == "4"
            habilitar_internet()
        elseif op == "0"
            show_cursor(); println("\n  Até logo!"); exit(0)
        else
            println("  $(R)Opção inválida.$(X)"); sleep(0.5)
        end
    end
end

# ── Entrada principal ─────────────────────────────────────
function main()
    mkpath("outputs")
    ranges = load_ranges()

    if !isempty(ARGS)
        # Parsing inicial dos argumentos
        puzzle_id = 0
        modo_id = 3
        cpu_val = Sys.CPU_THREADS
        pct = 0.0
        start_hex = ""

        i = 1
        while i <= length(ARGS)
            if ARGS[i] == "--puzzle"
                puzzle_id = parse(Int, ARGS[i+1])
                i += 2
            elseif ARGS[i] == "--modo"
                m_str = lowercase(ARGS[i+1])
                if m_str == "sequencial" || m_str == "1"; modo_id = 1
                elseif m_str == "reverso" || m_str == "2"; modo_id = 2
                elseif m_str == "aleatorio" || m_str == "3" || m_str == "aleatório"; modo_id = 3
                else; modo_id = 3
                end
                i += 2
            elseif ARGS[i] == "--cpus"
                cpu_val = parse(Int, ARGS[i+1])
                i += 2
            elseif ARGS[i] == "--porcentagem"
                pct = parse(Float64, ARGS[i+1])
                i += 2
            elseif ARGS[i] == "--start"
                start_hex = replace(ARGS[i+1], "0x" => "")
                i += 2
            else
                i += 1
            end
        end

        if puzzle_id > 0 && puzzle_id <= length(ranges)
            r = ranges[puzzle_id]
            CFG.wallet_num = puzzle_id
            CFG.wallet_addr = r["endereco"]
            CFG.interval_min = isempty(start_hex) ? replace(r["min"], "0x" => "") : start_hex
            CFG.interval_max = replace(r["max"], "0x" => "")
            CFG.cpus = cpu_val

            r_min = hex2big(CFG.interval_min)
            r_max = hex2big(CFG.interval_max)
            start_key = r_min

            if modo_id == 2
                start_key = r_max
            elseif pct > 0 && modo_id == 1
                p = pct > 2.0 ? pct / 100.0 : pct
                p = min(max(p, 0.0), 1.0)
                rng_size = r_max - r_min + 1
                offset = BigInt(floor(Float64(rng_size) * p))
                start_key = r_min + offset
            end

            println("$(G)=== BTC KEY HUNTER • HEADLESS/KAGGLE MODO ===$(X)")
            println("Puzzle : #$puzzle_id")
            println("Endereço: $(CFG.wallet_addr)")
            println("Modo   : $(modo_id == 1 ? "Sequencial" : modo_id == 2 ? "Reverso" : "Aleatório")")
            println("CPUs   : $cpu_val")
            println("Início : $(pct > 0 ? "$pct %" : "Padrão")")
            println("$(DIM)─────────────────────────────────────────────$(X)")
            
            scan_dashboard(CFG.wallet_addr, r_min, r_max, modo_id, start_key)
            exit(0)
        else
            println("$(R)Erro: Puzzle $puzzle_id inválido ou ausente.$(X)")
            println("Uso: julia main.jl --puzzle <id> [--modo 1|2|3] [--cpus <num>] [--porcentagem <float>] [--start <hex/dec>]")
            exit(1)
        end
    end

    # Execução normal interativa
    splash()
    escolher_cpus()
    habilitar_internet()
    escolher_carteira(ranges)
    main_menu()
end

main()
