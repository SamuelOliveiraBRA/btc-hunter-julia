using Pkg; Pkg.activate(".")
# ═══════════════════════════════════════════════════════════
#  BTC KEY HUNTER  ·  Julia Edition  ·  v2.1.0
#  Melhorias v2.0: Single-format hash, Checkpoint, Multi-target,
#                  Batch configurável, Random mode corrigido
#  Melhorias v2.1: BitCrackEngine (FastField+FastSecp) como motor
#                  alternativo selecionável
# ═══════════════════════════════════════════════════════════
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/CheckpointManager.jl")
include("src/BloomFilter.jl")
include("src/MultiTarget.jl")
include("btc_utils.jl")

using .Base58, .BtcCrypto, .BtcUtils
using .CheckpointManager
using .BloomFilter
using .MultiTarget

include("src/SecpOptimized.jl")
using .SecpOptimized
include("src/FastField.jl")
include("src/FastSecp.jl")
include("src/BitCrackEngine.jl")
using .FastField, .FastSecp, .BitCrackEngine
using HTTP, JSON, Random, Dates, Printf
using Base.Threads: @spawn, Atomic, atomic_add!
try
    using CUDA
catch
    # CUDA não disponível
end
include("src/GpuCrypto.jl")
include("src/scanner/GpuScanner.jl")
using .GpuCrypto, .GpuScanner

# ── Cores ANSI ────────────────────────────────────────────
const G  = "\e[32m";  const R  = "\e[31m";  const B  = "\e[94m"
const Y  = "\e[33m";  const M  = "\e[35m";  const C  = "\e[96m"
const W  = "\e[97m";  const DIM = "\e[2m";  const X  = "\e[0m"
const BOLD = "\e[1m"; const UL = "\e[4m"

# ── Config ────────────────────────────────────────────────
mutable struct Config
    cpus::Int; internet::Bool; gpu::Bool; gpu_intensity::Int
    wallet_num::Int; wallet_addr::String
    wallet_status::Int
    interval_min::String; interval_max::String
    saldo::String; mode::Int; running::Bool
    # v2.0: performance e checkpoint
    batch_size::Int       # Tamanho do lote por worker
    both_formats::Bool    # true = testa comprimido + não-comprimido
    use_checkpoint::Bool  # true = salva checkpoint automaticamente
    # v2.1: motor selecionável
    engine::Symbol        # :secp (padrão BigInt) | :bitcrack (FastField+FastSecp)
end

const CFG = Config(
    Sys.CPU_THREADS, false, false, 1,
    0, "", 0, "0x0", "0x0", "", 0, true,
    512, false, true,  # v2.0: batch=512, só comprimido, checkpoint ativo
    :secp              # v2.1: motor padrão (SecpOptimized + BigInt)
)

# ── Utilitários ───────────────────────────────────────────
ansi(s) = replace(s, r"\e\[[0-9;]*m" => "")
function clear(); print("\033[2J\033[H"); flush(stdout); end
goto(row, col=1) = print("\033[$(row);$(col)H")
hide_cursor() = print("\033[?25l")
show_cursor() = print("\033[?25h")
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
    "█" ^ filled * "░" ^ (width - filled)
end

load_ranges() = JSON.parsefile("data/ranges.json")["ranges"]

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
const W_BOX = 62

function box_line(content="", color="")
    raw = ansi(content)
    pad = max(0, W_BOX - length(raw))
    "║ $(color)$(content)$(X)$(repeat(" ", pad)) ║"
end

function box_top(title="")
    t = isempty(title) ? "" : " $title "
    left  = (W_BOX - length(t)) ÷ 2
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

# ── Health Check (novo v2.0) ──────────────────────────────
function check_health()::Vector{String}
    issues = String[]
    # Verifica threads Julia
    if Threads.nthreads() == 1
        push!(issues, "Julia iniciado com 1 thread! Use: julia --threads auto main.jl")
    end
    # Verifica libcrypto
    try
        BtcCrypto.hash160(UInt8[1, 2, 3])
    catch e
        push!(issues, "libcrypto não disponível: $(e)")
    end
    # Verifica dados
    isfile("data/ranges.json") || push!(issues, "data/ranges.json não encontrado")
    return issues
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
        "  $(W)Key Hunter  ·  Julia Edition  ·  $(G)v2.1.0$(X)",
        "  $(DIM)Motor: Secp256k1 + SHA256 + RIPEMD160$(X)",
        "  $(DIM)Novidades: Checkpoint • Multi-alvo • BitCrackEngine • Batch 512$(X)",
        "",
    ]
    foreach(println, lines)

    issues = check_health()
    if !isempty(issues)
        println("  $(Y)⚠  Avisos do sistema:$(X)")
        for issue in issues
            println("  $(R)!$(X) $(DIM)$(issue)$(X)")
        end
        println()
    end

    jt = Threads.nthreads()
    println("  $(G)✓$(X) $(DIM)Julia threads: $(jt) | CPUs detectadas: $(Sys.CPU_THREADS)$(X)")
    println("  $(G)✓$(X) $(DIM)Batch padrão: $(CFG.batch_size) | Checkpoint: $(CFG.use_checkpoint ? "Ativo" : "Off")$(X)")
    println("  $(G)✓$(X) $(DIM)Formato: $(CFG.both_formats ? "Comprimido + Não-comprimido" : "Apenas Comprimido (recomendado)")$(X)")
    println()
    sleep(0.8)
    show_cursor()
end

# ── Header fixo ───────────────────────────────────────────
function header(subtitle="")
    clear()
    cpu_bar = G * ("■" ^ CFG.cpus) * DIM * ("□" ^ (Sys.CPU_THREADS - CFG.cpus)) * X
    inet_s  = CFG.internet ? G*"● Ativa"*X : DIM*"○ Desativada"*X
    fmt_s   = CFG.both_formats ? C*"C+U"*X : G*"Comprimido"*X

    println(box_top("$(BOLD)$(W) BTC KEY HUNTER v2.1 $(X)"))
    eng_s   = ""
    if CFG.engine == :bitcrack; eng_s = M*"BitCrack"*X
    elseif CFG.engine == :bsgs; eng_s = Y*"BSGS"*X
    else; eng_s = G*"SecpOpt"*X
    end
    println(box_split("$(Y)v2.1.0$(X)  Julia Edition", "$(B)Lote:$(X)$(C)$(CFG.batch_size)$(X)  $(W)Fmt:$(X)$(fmt_s)  $(W)Motor:$(X)$eng_s"))
    println(box_sep())
    println(box_split("$(W)CPUs$(X)  $cpu_bar", "$(W)Internet$(X)  $inet_s"))

    if CFG.wallet_num > 0
        println(box_sep())
        st  = CFG.wallet_status == 0 ? "$(G)✓ Disponível$(X)" : "$(R)✗ Encontrada$(X)"
        rng_size = hex2big(CFG.interval_max) - hex2big(CFG.interval_min) + 1
        addr_short = length(CFG.wallet_addr) > 34 ? CFG.wallet_addr[1:34] : CFG.wallet_addr
        ckpt_ind = has_checkpoint(CFG.wallet_num) ? "  $(C)⏸ checkpoint$(X)" : ""
        println(box_line("$(Y)#$(CFG.wallet_num)$(X)  $(W)$(addr_short)$(X)$(ckpt_ind)"))
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

# ── Configuração de CPUs ──────────────────────────────────
function escolher_cpus()
    n = Sys.CPU_THREADS
    while true
        header("Configuração › CPUs")
        println("  Detectadas: $(G)$n$(X) threads lógicas")
        println("  $(DIM)Julia threads ativos: $(Threads.nthreads())$(X)\n")
        bars = String[]
        for i in 1:n
            if n <= 16
                bar_str = G * ("■"^i) * DIM * ("□"^(n-i)) * X
                push!(bars, "$(i) $(bar_str)")
            else
                push!(bars, "$(G)$(i)$(X)")
            end
        end
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
        println("\n  $(R)● Valor inválido.$(X)")
        sleep(1)
    end
end

# ── Configuração de internet ──────────────────────────────
function habilitar_internet()
    header("Configuração › Internet")
    println("  Habilitar consulta de saldo via blockchain.info?\n")
    println("  $(G)[1]$(X)  Sim — consultar saldo")
    println("  $(R)[2]$(X)  Não — modo offline\n")
    while true
        op = input("  Opção: ")
        op == "1" && (CFG.internet = true;  return)
        op == "2" && (CFG.internet = false; return)
        print("\r  $(R)Opção inválida.$(X)"); sleep(0.5)
    end
end

# ── Configurações Avançadas (novo v2.0) ───────────────────
function config_avancado()
    while true
        header("Configuração › Avançado")
        fmt_s  = CFG.both_formats ? "$(C)Comprimido + Não-comprimido$(X)" : "$(G)Apenas Comprimido$(X) $(DIM)(rápido)$(X)"
        ckpt_s = CFG.use_checkpoint ? "$(G)Ativo$(X)" : "$(R)Desativado$(X)"
        eng_s  = ""
        if CFG.engine == :bitcrack; eng_s = "$(M)BitCrackEngine$(X) $(DIM)(FastField+FastSecp)$(X)"
        elseif CFG.engine == :bsgs; eng_s = "$(Y)BSGSEngine$(X) $(DIM)(Baby-Step Giant-Step RAM)$(X)"
        else; eng_s = "$(G)SecpOptimized$(X) $(DIM)(BigInt, padrão)$(X)"
        end

        println("  $(W)Opções avançadas de performance:\n$(X)")
        println("  $(B)[1]$(X)  Tamanho do lote    $(DIM)— atual: $(G)$(CFG.batch_size)$(X) $(DIM)chaves/lote$(X)")
        println("  $(Y)[2]$(X)  Formato de hash    $(DIM)— $fmt_s$(X)")
        println("  $(C)[3]$(X)  Checkpoint automát. $(DIM)— $ckpt_s$(X)")
        println("  $(M)[4]$(X)  Motor de busca     $(DIM)— $eng_s$(X)")
        println("  $(DIM)[0]  Voltar$(X)\n")

        op = input("  Opção: ")
        if op == "1"
            s = input("  Lote (potência de 2, ex: 128/256/512/1024): ")
            v = tryparse(Int, strip(s))
            if !isnothing(v) && v > 0
                CFG.batch_size = v
                println("  $(G)✓ Lote configurado: $v$(X)"); sleep(0.8)
            else
                println("  $(R)Valor inválido.$(X)"); sleep(0.8)
            end
        elseif op == "2"
            CFG.both_formats = !CFG.both_formats
            msg = CFG.both_formats ? "$(C)C+U ativado$(X) (mais lento)" : "$(G)Apenas Comprimido$(X) (rápido)"
            println("  ● $msg"); sleep(0.8)
        elseif op == "3"
            CFG.use_checkpoint = !CFG.use_checkpoint
            msg = CFG.use_checkpoint ? "$(G)Checkpoint ativado$(X)" : "$(R)Checkpoint desativado$(X)"
            println("  ● $msg"); sleep(0.8)
        elseif op == "4"
            if CFG.engine == :secp
                CFG.engine = :bitcrack
                msg = "$(M)BitCrackEngine$(X) (FastField+FastSecp)"
            elseif CFG.engine == :bitcrack
                CFG.engine = :bsgs
                msg = "$(Y)BSGSEngine$(X) (Baby-Step Giant-Step RAM)"
            else
                CFG.engine = :secp
                msg = "$(G)SecpOptimized$(X) (BigInt, padrão)"
            end
            println("  ● Motor: $msg"); sleep(1.0)
        elseif op == "0"
            return
        end
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
            r    = ranges[i]
            st   = r["status"] == 0 ? G*"✓"*X : R*"✗"*X
            addr = isempty(r["endereco"]) ? DIM*"(sem alvo)"*X : Y*r["endereco"][1:min(end,18)]*"..."*X
            ckpt = has_checkpoint(i) ? " $(C)⏸$(X)" : ""
            num_str = lpad(i, 3)
            min_str = rpad(r["min"][1:min(end,16)], 16)
            println("  $num_str  $st       $(DIM)$(min_str)$(X)  $addr$ckpt")
        end

        println()
        nav = []
        page > 1     && push!(nav, "$(B)[A]$(X) Anterior")
        page < pages && push!(nav, "$(B)[P]$(X) Próxima")
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
                        res  = HTTP.get("https://blockchain.info/balance?active=$(CFG.wallet_addr)",
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

# ── Dashboard de scan v2.0 ────────────────────────────────
function scan_dashboard(
    target_addrs::Vector{String},
    rng_min::BigInt, rng_max::BigInt,
    mode::Int,
    start_key::BigInt = rng_min;
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
        clear(); hide_cursor()
        println(box_top("$(BOLD)$(W) BTC KEY HUNTER v2.1  ·  Julia Edition $(X)"))
        hw_str  = CFG.gpu ? "$(G)GPU+$(CFG.cpus)T$(X)" : "$(G)$(CFG.cpus) threads$(X)"
        fmt_str = CFG.both_formats ? "$(C)C+U$(X)" : "$(G)C$(X)"
        eng_str = ""
        if CFG.engine == :bitcrack; eng_str = M*"BitCrack"*X
        elseif CFG.engine == :bsgs; eng_str = Y*"BSGS"*X
        else; eng_str = G*"SecpOpt"*X
        end
        println(box_split("$(Y)Modo$(X)  $mode_name", "$(W)HW$(X) $hw_str  $(W)Lote$(X):$(C)$(batch_sz)$(X)  $(W)Motor$(X):$eng_str"))
        println(box_sep())
        if n_targets == 1
            println(box_line("$(W)🎯 Alvo$(X)   $(Y)$(target_addrs[1])$(X)"))
        else
            println(box_line("$(W)🎯 Alvos$(X)  $(C)$(n_targets) endereços carregados$(X)"))
        end
        println(box_split(
            "$(DIM)Min$(X)  $(C)$(CFG.interval_min)$(X)",
            "$(DIM)Max$(X)  $(C)$(CFG.interval_max)$(X)"
        ))
        if puzzle_id > 0 && CFG.use_checkpoint
            println(box_line("$(DIM)Checkpoint ativo │ Puzzle #$(puzzle_id) │ salva a cada 30s$(X)"))
        end
        println(box_sep())
        flush(stdout)
    end

    # ── Stats dinâmicos ───────────────────────────────────
    function render_stats(speed, elapsed, found=false)
        cur     = keys_done[]
        pct     = rng_size > 0 ? min(1.0, cur / Float64(rng_size)) : 0.0
        lk_str  = lpad(string(last_key[], base=16), 16, "0")
        eta     = speed > 0 && !found ? (Float64(rng_size) - cur) / speed : 0.0
        print("\033[J")

        if found
            fk_hex = lpad(string(found_key[], base=16), 64, "0")
            println(box_line("$(G)$(BOLD)✅ CHAVE ENCONTRADA!$(X)"))
            println(box_line("$(W)Privada$(X)  $(G)...$(fk_hex[end-15:end])$(X)"))
            println(box_line(""))
            println(box_line(""))
        else
            sp = spinner[spin_idx[]]
            spin_idx[] = mod1(spin_idx[] + 1, length(spinner))
            println(box_split(
                "$(W)Chave$(X)   $(C)0x$(lk_str)$(X)",
                "$(W)Tempo$(X)   $(Y)$(fmt_time(round(Int, elapsed)))$(X)"
            ))
            println(box_split(
                "$(W)Testadas$(X)  $(G)$(fmt_num(cur))$(X)",
                "$(W)Veloc.$(X)   $(G)$(fmt_num(speed))$(X)/s  $(C)$sp$(X)"
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

            print("\033[7A")
            render_stats(speed, total_elapsed)

            # Checkpoint a cada 30s (apenas seq/reverso)
            if CFG.use_checkpoint && puzzle_id > 0 && mode != 3
                if (now_t - last_ckpt_t) >= 30.0
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

    # ── Workers de busca (v2.1 — motor selecionável) ───────
    n_threads = CFG.cpus
    safe_rng_max = rng_max - BigInt(batch_sz * n_threads)

    # Pré-cálculo dos passos (apenas motor :secp)
    G_step           = CFG.engine == :secp ? SecpOptimized.scalar_mul(BigInt(n_threads), SecpOptimized.G_J) : SecpOptimized.G_J
    G_batch_step     = CFG.engine == :secp ? SecpOptimized.scalar_mul(BigInt(batch_sz * n_threads), SecpOptimized.G_J) : SecpOptimized.G_J
    G_batch_step_neg = CFG.engine == :secp ? SecpOptimized.negate_point_jacobian(G_batch_step) : SecpOptimized.G_J

    worker_tasks = map(1:n_threads) do wid
        @spawn begin
            curr_base = if mode == 1
                if CFG.engine == :bitcrack
                    start_key + BigInt((wid - 1) * batch_sz)
                else
                    start_key + BigInt(wid - 1)
                end
            elseif mode == 2
                if CFG.engine == :bitcrack
                    start_key - BigInt((wid - 1) * batch_sz)
                else
                    start_key - BigInt(wid - 1)
                end
            else
                r_safe = safe_rng_max > rng_min ? safe_rng_max : rng_max
                BigInt(rand(rng_min:r_safe))
            end

            if CFG.engine == :bitcrack
                # ────── Motor BitCrackEngine (FastField + FastSecp) ──────
                # Suporta apenas single-target via hash160 direto
                first_h160 = BtcCrypto.base58_to_hash160(target_addrs[1])
                state = BitCrackEngine.init_engine(curr_base, first_h160, batch_sz, batch_sz * n_threads, CFG.both_formats)

                while !stop[]
                    idx = BitCrackEngine.check_batch(state)

                    if idx > 0
                        found_key[]  = curr_base + BigInt(idx - 1)
                        found_addr[] = target_addrs[1]
                        stop[] = true; break
                    end

                    atomic_add!(keys_done, batch_sz)

                    if mode == 1
                        curr_base += BigInt(batch_sz * n_threads)
                        BitCrackEngine.next_batch!(state)
                    elseif mode == 2
                        curr_base -= BigInt(batch_sz * n_threads)
                        # No modo reverso, re-inicializamos o motor no novo curr_base
                        # ja que o stride_J do motor e sempre positivo.
                        state = BitCrackEngine.init_engine(curr_base, first_h160, batch_sz, batch_sz * n_threads, CFG.both_formats)
                    else
                        r_safe = safe_rng_max > rng_min ? safe_rng_max : rng_max
                        curr_base = BigInt(rand(rng_min:r_safe))
                        state = BitCrackEngine.init_engine(curr_base, first_h160, batch_sz, batch_sz * n_threads, CFG.both_formats)
                    end

                    last_key[] = curr_base
                    yield()

                    if mode == 1 && curr_base > rng_max; break; end
                    if mode == 2 && curr_base < rng_min; break; end
                end
            else
                # ────── Motor SecpOptimized (BigInt Jacobian) — padrão ───
                P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
                batch_points = Vector{SecpOptimized.PointJacobian}(undef, batch_sz)

                while !stop[]
                # 1. Gerar lote via adição incremental O(batch_sz)
                P_temp = P_base
                for i in 1:batch_sz
                    batch_points[i] = P_temp
                    P_temp = SecpOptimized.add_points_jacobian(P_temp, G_step)
                end

                # 2. Montgomery Batch Inversion → uma única inversão modular
                affine_pts = SecpOptimized.batch_normalize(batch_points)

                # 3. Serializar comprimido (padrão) — só serializa não-comprimido se necessário
                pubs_comp = BtcCrypto.serialize_compressed_batch(affine_pts)

                # 4. Verificar hits
                found_in_batch = false
                for i in 1:batch_sz
                    h160_c = BtcCrypto.hash160(pubs_comp[i])

                    if check_hit(target_set, h160_c)
                        found_key[]  = curr_base + BigInt((i - 1) * n_threads)
                        found_addr[] = address_from_hash(target_set, h160_c)
                        stop[] = true
                        found_in_batch = true
                        break
                    end

                    # Verifica formato não-comprimido apenas se ativado
                    if CFG.both_formats
                        pub_uncomp = BtcCrypto.serialize_uncompressed_batch([affine_pts[i]])[1]
                        h160_u = BtcCrypto.hash160(pub_uncomp)
                        if check_hit(target_set, h160_u)
                            found_key[]  = curr_base + BigInt((i - 1) * n_threads)
                            found_addr[] = address_from_hash(target_set, h160_u)
                            stop[] = true
                            found_in_batch = true
                            break
                        end
                    end
                end

                found_in_batch && break
                stop[] && break

                atomic_add!(keys_done, batch_sz)

                # Avançar base do lote
                if mode == 1
                    curr_base += BigInt(batch_sz * n_threads)
                    P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step)
                elseif mode == 2
                    curr_base -= BigInt(batch_sz * n_threads)
                    P_base = SecpOptimized.add_points_jacobian(P_base, G_batch_step_neg)
                else
                    # Aleatório: novo ponto de partida, mas reutiliza lote incremental
                    r_safe = safe_rng_max > rng_min ? safe_rng_max : rng_max
                    curr_base = BigInt(rand(rng_min:r_safe))
                    P_base = SecpOptimized.scalar_mul(curr_base, SecpOptimized.G_J)
                end

                    last_key[] = curr_base
                    yield()

                    if mode == 1 && curr_base > rng_max; break; end
                    if mode == 2 && curr_base < rng_min; break; end
                end
                # fim motor :secp
            end # if CFG.engine

            stop[] = true
        end # @spawn
    end # map

    foreach(wait, worker_tasks)
    stop[] = true
    wait(progress_task)

    total_elapsed = base_elapsed + (time() - session_start)
    final  = keys_done[]
    speed  = total_elapsed > 0 ? final / total_elapsed : 0.0

    if found_key[] >= 0
        pk     = found_key[]
        pk_hex = lpad(string(pk, base=16), 64, "0")
        wif    = BtcUtils.generate_wif(pk)
        pub_hex = bytes2hex(BtcCrypto.priv_to_pub_compressed(pk))
        addr   = isempty(found_addr[]) ? (isempty(target_addrs) ? "" : target_addrs[1]) : found_addr[]

        render_stats(speed, total_elapsed, true)
        println()
        println("  $(G)$(BOLD)Endereço$(X) : $(Y)$(addr)$(X)")
        println("  $(G)$(BOLD)Privada$(X)  : $(Y)$(pk_hex)$(X)")
        println("  $(G)$(BOLD)WIF$(X)      : $(Y)$(wif)$(X)")
        println("  $(G)$(BOLD)Pública$(X)  : $(Y)$(pub_hex)$(X)")
        println()
        salvar_encontrada(pk_hex, addr, wif, pub_hex)
        println("  $(G)✓ Salvo em outputs/encontradas.txt$(X)")

        # Remove checkpoint ao encontrar a chave
        puzzle_id > 0 && CheckpointManager.delete_checkpoint(puzzle_id)
    else
        # Salva checkpoint final para retomada (seq/reverso)
        if CFG.use_checkpoint && puzzle_id > 0 && mode != 3
            try
                CheckpointManager.save_checkpoint(puzzle_id, last_key[], final, mode, total_elapsed)
                println()
                println("  $(C)⏸ Checkpoint salvo em outputs/checkpoint_puzzle_$(puzzle_id).json$(X)")
            catch; end
        end

        println()
        println(box_top("$(W) SESSÃO CONCLUÍDA $(X)"))
        println(box_line("$(DIM)Chave não encontrada no intervalo.$(X)"))
        println(box_sep())
        println(box_split("$(W)Testadas$(X)  $(G)$(fmt_num(final))$(X)", "$(W)Tempo$(X) $(Y)$(fmt_time(round(Int,total_elapsed)))$(X)"))
        println(box_split("$(W)Velocidade$(X) $(G)$(fmt_num(speed))$(X)/s", "$(W)Modo$(X) $mode_name"))
        println(box_split("$(W)Alvos$(X) $(C)$(n_targets)$(X)", "$(W)Lote$(X) $(C)$(batch_sz)$(X)  $(W)Fmt$(X) $(CFG.both_formats ? "C+U" : "C")$(X)"))
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

    # Verifica checkpoint existente
    ckpt = CFG.use_checkpoint ? CheckpointManager.load_checkpoint(CFG.wallet_num) : nothing
    if ckpt !== nothing
        println("  $(C)⏸ Checkpoint encontrado para o Puzzle #$(CFG.wallet_num)$(X)")
        println("  $(DIM)Salvo em: $(ckpt.saved_at)$(X)")
        println("  $(DIM)Progresso: $(fmt_num(ckpt.keys_done)) chaves testadas$(X)")
        println("  $(DIM)Última chave: 0x$(lpad(string(ckpt.current_key, base=16), 16, "0"))$(X)")
        println()
        println("  $(G)[1]$(X)  Retomar de onde parou")
        println("  $(Y)[2]$(X)  Iniciar do começo (descarta checkpoint)")
        println("  $(DIM)[0]  Voltar$(X)\n")
        op_ckpt = input("  Opção: ")
        if op_ckpt == "1"
            mode_ckpt = ckpt.mode
            scan_dashboard([addr], r_min, r_max, mode_ckpt, ckpt.current_key, puzzle_id=CFG.wallet_num)
            return
        elseif op_ckpt == "2"
            CheckpointManager.delete_checkpoint(CFG.wallet_num)
            println("  $(R)✗ Checkpoint descartado.$(X)"); sleep(0.5)
        elseif op_ckpt == "0"
            return
        end
        println()
    end

    println("  $(W)Escolha o modo de escaneamento:$(X)\n")
    println("  $(G)[1]$(X)  Sequencial →     começar do menor valor")
    println("  $(B)[2]$(X)  ← Reverso         começar do maior valor")
    println("  $(M)[3]$(X)  ⟳ Aleatório       valores aleatórios no intervalo")
    println("  $(C)[4]$(X)  % Porcentagem     escolher a partir de qual % inicializar")
    println("  $(DIM)[5]  Voltar$(X)\n")

    op = input("  Opção: ")
    rng_size = r_max - r_min + 1

    if op == "1"
        scan_dashboard([addr], r_min, r_max, 1, r_min, puzzle_id=CFG.wallet_num)
    elseif op == "2"
        scan_dashboard([addr], r_min, r_max, 2, r_max, puzzle_id=CFG.wallet_num)
    elseif op == "3"
        scan_dashboard([addr], r_min, r_max, 3, r_min, puzzle_id=CFG.wallet_num)
    elseif op == "4"
        str_pct = input("  $(W)Digite a % inicial (ex: 40 ou 0.40): $(X)")
        pct_input = tryparse(Float64, replace(str_pct, "," => "."))
        if pct_input !== nothing
            # Converte para 0.0-1.0 independente do formato (40 ou 0.40)
            pct = pct_input > 1.0 ? pct_input / 100.0 : pct_input
            pct = min(max(pct, 0.0), 1.0)
            
            # Cálculo de alta precisão com BigInt
            # Multiplicamos r_size por um fator grande antes de dividir
            # para manter a precisão total sem depender de Float64
            factor = BigInt(1_000_000_000)
            pct_big = BigInt(floor(pct * 1_000_000_000))
            offset = (rng_size * pct_big) ÷ factor
            
            start_key = r_min + offset
            
            println("\n  $(G)→ Ponto de partida calculado:$(X)")
            println("  $(W)Chave:$(X) 0x$(string(start_key, base=16))")
            println("  $(W)Posição:$(X) $(round(pct*100, digits=4))%\n")
            sleep(1.5)
            
            scan_dashboard([addr], r_min, r_max, 1, start_key, puzzle_id=CFG.wallet_num)
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

        println("  $(G)[1]$(X)  $(W)Iniciar busca$(X)       $(DIM)— escanear chaves privadas$(X)")
        println("  $(Y)[2]$(X)  Escolher carteira    $(DIM)— trocar puzzle alvo$(X)")
        println("  $(B)[3]$(X)  Configurar CPUs      $(DIM)— em uso: $(G)$(CFG.cpus)$(X)")
        println("  $(C)[4]$(X)  Configurar internet  $(DIM)— $(CFG.internet ? G*"ativa"*X : DIM*"desativada"*X)$(X)")
        println("  $(M)[5]$(X)  Configurações avançadas $(DIM)— lote, formato, checkpoint$(X)")
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
        elseif op == "5"
            config_avancado()
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
        puzzle_id = 0
        modo_id   = 3
        cpu_val   = Sys.CPU_THREADS
        pct       = 0.0
        start_hex = ""

        i = 1
        while i <= length(ARGS)
            if ARGS[i] == "--puzzle"
                puzzle_id = parse(Int, ARGS[i+1]); i += 2
            elseif ARGS[i] == "--modo"
                m_str = lowercase(ARGS[i+1])
                if m_str in ("sequencial", "1"); modo_id = 1
                elseif m_str in ("reverso", "2"); modo_id = 2
                else; modo_id = 3
                end
                i += 2
            elseif startswith(ARGS[i], "--gpu")
                CFG.gpu = true
                if contains(ARGS[i], ":")
                    parts = split(ARGS[i], ":")
                    length(parts) == 2 && (v = tryparse(Int, parts[2]); v !== nothing && (CFG.gpu_intensity = v))
                end
                i += 1
            elseif ARGS[i] == "--cpus"
                cpu_val = parse(Int, ARGS[i+1]); i += 2
            elseif ARGS[i] == "--porcentagem"
                pct = parse(Float64, ARGS[i+1]); i += 2
            elseif ARGS[i] == "--start"
                start_hex = replace(ARGS[i+1], "0x" => ""); i += 2
            elseif ARGS[i] == "--batch"
                CFG.batch_size = parse(Int, ARGS[i+1]); i += 2
            elseif ARGS[i] == "--ambos-formatos"
                CFG.both_formats = true; i += 1
            elseif ARGS[i] == "--sem-checkpoint"
                CFG.use_checkpoint = false; i += 1
            elseif ARGS[i] == "--motor"
                m_str = lowercase(ARGS[i+1])
                if m_str == "bitcrack"; CFG.engine = :bitcrack
                elseif m_str == "bsgs"; CFG.engine = :bsgs
                else; CFG.engine = :secp
                end
                i += 2
            else
                i += 1
            end
        end

        if puzzle_id > 0 && puzzle_id <= length(ranges)
            r = ranges[puzzle_id]
            CFG.wallet_num    = puzzle_id
            CFG.wallet_addr   = r["endereco"]
            CFG.interval_min  = isempty(start_hex) ? replace(r["min"], "0x" => "") : start_hex
            CFG.interval_max  = replace(r["max"], "0x" => "")
            CFG.cpus          = cpu_val

            r_min     = hex2big(CFG.interval_min)
            r_max     = hex2big(CFG.interval_max)
            start_key = r_min

            if modo_id == 2
                start_key = r_max
            elseif pct > 0 && modo_id == 1
                p = pct > 2.0 ? pct / 100.0 : pct
                p = min(max(p, 0.0), 1.0)
                
                # Cálculo de alta precisão com BigInt (evita Float64 nos puzzles grandes)
                factor    = BigInt(1_000_000_000)
                p_big     = BigInt(floor(p * 1_000_000_000))
                rng_size  = r_max - r_min + 1
                offset    = (rng_size * p_big) ÷ factor
                start_key = r_min + offset
            end

            println("$(G)=== BTC KEY HUNTER v2.0 • HEADLESS MODO ===$(X)")
            println("Puzzle   : #$puzzle_id")
            println("Endereço : $(CFG.wallet_addr)")
            println("Modo     : $(modo_id == 1 ? "Sequencial" : modo_id == 2 ? "Reverso" : "Aleatório")")
            println("CPUs     : $cpu_val | Batch: $(CFG.batch_size)")
            println("Formato  : $(CFG.both_formats ? "Comprimido + Não-comprimido" : "Apenas Comprimido")")
            println("Checkpoint: $(CFG.use_checkpoint ? "Ativo" : "Desativado")")
            println("$(DIM)─────────────────────────────────────────────$(X)")

            if CFG.gpu && !(try CUDA.functional() catch; false end)
                println("$(R)⚠ GPU solicitada mas não funcional.$(X)")
                CFG.gpu = false; sleep(2)
            end

            scan_dashboard([CFG.wallet_addr], r_min, r_max, modo_id, start_key, puzzle_id=puzzle_id)
            exit(0)
        else
            println("$(R)Erro: Puzzle $puzzle_id inválido.$(X)")
            println("Uso: julia main.jl --puzzle <id> [--modo 1|2|3] [--cpus <n>] [--batch <n>]")
            println("     [--porcentagem <f>] [--start <hex>] [--ambos-formatos] [--sem-checkpoint]")
            exit(1)
        end
    end

    # Execução interativa
    splash()
    escolher_cpus()
    habilitar_internet()
    escolher_carteira(ranges)
    main_menu()
end

main()
