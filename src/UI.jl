module UIModule

using Printf
using ..ConfigModule: CFG

export G, R, B, Y, M, C, W, DIM, X, BOLD, UL
export clear, goto, hide_cursor, show_cursor, input, fmt_num, fmt_time, progress_bar
export box_line, box_top, box_sep, box_bot, box_split, header, splash

# ── Cores ANSI ────────────────────────────────────────────
const G  = "\e[32m";  const R  = "\e[31m";  const B  = "\e[94m"
const Y  = "\e[33m";  const M  = "\e[35m";  const C  = "\e[96m"
const W  = "\e[97m";  const DIM = "\e[2m";  const X  = "\e[0m"
const BOLD = "\e[1m"; const UL = "\e[4m"

# ── Utilitários ───────────────────────────────────────────
ansi(s) = replace(s, r"\e\[[0-9;]*m" => "")
# Limpa tela, limpa scrollback e move cursor para o topo (1,1)
clear() = (print("\e[2J\e[3J\e[H"); flush(stdout))
goto(row, col=1) = print("\033[$(row);$(col)H")
hide_cursor() = print("\033[?25l")
show_cursor() = print("\033[?25h")
input(prompt) = (show_cursor(); print(prompt); r = readline(); hide_cursor(); r)

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

# ── Box helpers ───────────────────────────────────────────
const W_BOX = 62

function box_line(content="", color="")
    raw = ansi(content)
    pad = max(0, W_BOX - length(raw))
    "║ $(color)$(content)$(X)$(repeat(" ", pad)) ║"
end

function box_top(title="")
    t = isempty(title) ? "" : " $title "
    total_w = W_BOX + 2
    left  = (total_w - length(ansi(t))) ÷ 2
    right = total_w - left - length(ansi(t))
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

function header(subtitle="")
    clear()
    # Logo BTC ASCII Art
    println("$(BOLD)$(B)  ██████╗ ████████╗ ██████╗")
    println("  ██╔══██╗╚══██╔══╝██╔════╝")
    println("  ██████╔╝   ██║   ██║")
    println("  ██╔══██╗   ██║   ██║")
    println("  ██████╔╝   ██║   ╚██████╗")
    println("  ╚═════╝    ╚═╝    ╚═════╝$(X)\n")

    cpu_bar = G * ("■" ^ CFG.cpus) * DIM * ("□" ^ (Sys.CPU_THREADS - CFG.cpus)) * X * " $(DIM)$(CFG.cpus)/$(Sys.CPU_THREADS)$(X)"
    gpu_bar = CFG.gpu ? (C * ("■" ^ (clamp(CFG.gpu_intensity ÷ 2, 1, 8))) * DIM * ("□" ^ (max(0, 8 - (CFG.gpu_intensity ÷ 2)))) * X) : (DIM * "Desativada" * X)
    inet_s  = CFG.internet ? G*"● Ativa"*X : DIM*"○ Desativada"*X
    fmt_s   = CFG.both_formats ? C*"C+U"*X : G*"Comprimido"*X

    println(box_top("$(BOLD)$(W) BTC HUNTER JULIA v1.5 $(X)"))
    eng_s   = ""
    if CFG.engine == :bitcrack; eng_s = M*"BitCrack"*X
    elseif CFG.engine == :bsgs; eng_s = Y*"BSGS"*X
    elseif CFG.engine == :gpu; eng_s = C*"CUDA/GPU"*X
    else; eng_s = G*"SecpOpt"*X
    end
    println(box_split("$(Y)v1.5.0$(X)  Julia Edition", "$(B)Dev. Samuel Oliveira$(X)"))
    println(box_sep())
    println(box_split("$(W)CPUs$(X)  $cpu_bar", "$(W)GPU$(X)   $gpu_bar"))
    println(box_split("$(W)Motor$(X)  $eng_s", "$(W)Internet$(X)  $inet_s"))
    println(box_split("$(W)Formato$(X)  $fmt_s", "$(W)Lote$(X)  $(C)$(CFG.batch_size)$(X)"))

    if CFG.wallet_num > 0
        println(box_sep())
        st  = CFG.wallet_status == 0 ? "$(G)✓ Disponível$(X)" : "$(R)✗ Encontrada$(X)"
        _min = replace(CFG.interval_min, "0x" => "", "0X" => "")
        _max = replace(CFG.interval_max, "0x" => "", "0X" => "")
        rng_size = parse(BigInt, _max, base=16) - parse(BigInt, _min, base=16) + 1
        addr_short = length(CFG.wallet_addr) > 34 ? CFG.wallet_addr[1:34] : CFG.wallet_addr
        println(box_line("$(Y)#$(CFG.wallet_num)$(X)  $(W)$(addr_short)$(X)"))
        println(box_sep())
        saldo_s = isempty(CFG.saldo) ? "$(DIM)---$(X)" : "$(G)$(CFG.saldo) BTC$(X)"
        println(box_split("$(W)Status$(X) $st", "$(W)Saldo$(X)  $saldo_s"))
        println(box_split(
            "$(DIM)Min:$(X)  $(Y)$(CFG.interval_min)$(X)",
            "$(DIM)Max:$(X)  $(Y)$(CFG.interval_max)$(X)"
        ))
        println(box_line("$(W)Range$(X)  $(C)$(fmt_num(rng_size))$(X) chaves"))
    end

    if !isempty(subtitle)
        println(box_sep())
        println(box_line("  $(M)$(subtitle)$(X)"))
    end
    println(box_bot())
    println()
end

function splash()
    header("Iniciando Sistema")
    sleep(0.5)
end

end # module
