module UIModule

using Printf
using ..ConfigModule: CFG

export G, R, B, Y, M, C, W, DIM, X, BOLD, UL
export clear, goto, hide_cursor, show_cursor, input, fmt_num, fmt_time, progress_bar, range_map, position_map
export box_line, box_top, box_sep, box_bot, box_split, header, splash, print_found_key

# ── Cores ANSI ────────────────────────────────────────────
const G  = "\e[32m";  const R  = "\e[31m";  const B  = "\e[94m"
const Y  = "\e[33m";  const M  = "\e[35m";  const C  = "\e[96m"
const W  = "\e[97m";  const DIM = "\e[2m";  const X  = "\e[0m"
const BOLD = "\e[1m"; const UL = "\e[4m"

# ── Info Hardware ──────────────────────────────────────────
function get_hw_info()
    os = Sys.isapple() ? "macOS" : Sys.iswindows() ? "Windows" : "Linux"
    cpus = Sys.cpu_info()
    model = isempty(cpus) ? "Desconhecido" : cpus[1].model
    speed = isempty(cpus) ? 0 : cpus[1].speed # MHz
    ram = round(Sys.total_memory() / 1024^3, digits=1)
    
    speed_s = speed > 1000 ? @sprintf("%.2f GHz", speed/1000) : "$speed MHz"
    return (os=os, model=model, speed=speed_s, ram="$(ram) GB")
end

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
    filled = round(Int, clamp(pct, 0, 1) * width)
    "█" ^ filled * "░" ^ (width - filled)
end

function range_map(p_start::Float64, p_end::Float64, width::Int=46)
    s, e = min(p_start, p_end), max(p_start, p_end)
    s_idx = round(Int, clamp(s, 0.0, 1.0) * width)
    e_idx = round(Int, clamp(e, 0.0, 1.0) * width)
    
    if s_idx == e_idx && e > s
        e_idx = min(width, e_idx + 1)
    end
    
    bar = ""
    for i in 1:width
        if i < s_idx
            bar *= DIM * "░" * X
        elseif i <= e_idx
            bar *= G * "█" * X
        else
            bar *= DIM * "░" * X
        end
    end
    return "[ " * bar * " ]"
end

function position_map(pos::Float64, width::Int=34)
    idx = clamp(round(Int, pos * (width - 1)), 0, width - 1) + 1
    bar = ""
    for i in 1:width
        if i == idx
            bar *= C * "◉" * X
        else
            bar *= DIM * "░" * X
        end
    end
    return "[" * bar * "]"
end

# ── Box helpers ───────────────────────────────────────────
const W_BOX = 62

function box_line(content="", color="")
    raw = ansi(content)
    pad = max(0, W_BOX - textwidth(raw))
    "║ $(color)$(content)$(X)$(repeat(" ", pad)) ║"
end

function box_top(title="")
    t = isempty(title) ? "" : " $title "
    total_w = W_BOX + 2
    tw = textwidth(ansi(t))
    left  = (total_w - tw) ÷ 2
    right = total_w - left - tw
    "╔$(repeat("═", left))$(t)$(repeat("═", right))╗"
end

box_sep() = "╠$(repeat("═", W_BOX+2))╣"
box_bot() = "╚$(repeat("═", W_BOX+2))╝"

function box_split(left, right, lw=30, color_l="", color_r="")
    raw_l = ansi(left); raw_r = ansi(right)
    pad_l = max(0, lw - textwidth(raw_l))
    pad_r = max(0, W_BOX - lw - 3 - textwidth(raw_r))
    "║ $(color_l)$(left)$(X)$(repeat(" ", pad_l)) │ $(color_r)$(right)$(X)$(repeat(" ", pad_r)) ║"
end

function header(subtitle=""; compact=false)
    clear()
    if !compact
        println()
        println("$(BOLD)$(B)  ██████╗ ████████╗ ██████╗")
        println("  ██╔══██╗╚══██╔══╝██╔════╝")
        println("  ██████╔╝   ██║   ██║")
        println("  ██╔══██╗   ██║   ██║")
        println("  ██████╔╝   ██║   ╚██████╗")
        println("  ╚═════╝    ╚═╝    ╚═════╝$(X)\n")
    end

    active_threads = Threads.nthreads()
    total_slots = max(active_threads, CFG.cpus, 1)
    cpu_bar = G * ("■" ^ active_threads) * DIM * ("□" ^ max(0, total_slots - active_threads)) * X * " $(DIM)$(active_threads)/$(total_slots)$(X)"
    gpu_bar = CFG.gpu ? (C * ("■" ^ (clamp(CFG.gpu_intensity ÷ 256, 1, 8))) * DIM * ("□" ^ (max(0, 8 - (CFG.gpu_intensity ÷ 256)))) * X * " $(DIM)$(CFG.gpu_intensity)$(X)") : (DIM * "Desativada" * X)
    inet_s  = CFG.internet ? G*"● Ativa"*X : DIM*"○ Desativada"*X
    fmt_s   = CFG.both_formats ? C*"C+U"*X : G*"Comprimido"*X
    b_size = CFG.engine == :gpu ? (CFG.gpu_intensity * 1024) : CFG.batch_size

    println(box_top("$(BOLD)$(W) BTC HUNTER JULIA v1.5.1 $(X)"))

    if !compact
        eng_s   = ""
        if CFG.engine == :bitcrack; eng_s = M*"BitCrack"*X
        elseif CFG.engine == :bsgs; eng_s = Y*"BSGS"*X
        elseif CFG.engine == :gpu
            eng_s = Sys.isapple() ? C*"Metal/Apple"*X : C*"CUDA/GPU"*X
        else; eng_s = G*"SecpOpt"*X
        end
        hw = get_hw_info()
        println(box_split("$(Y)v1.5.1$(X)  Julia Edition", "$(B)Dev. Samuel Oliveira$(X)"))
        println(box_sep())
        println(box_split("$(DIM)SISTEMA:$(X) $(W)$(hw.os) @ $(hw.speed)$(X)", "$(DIM)RAM:$(X) $(W)$(hw.ram)$(X)"))
        println(box_sep())
        
        if CFG.gpu && !isempty(CFG.gpu_name)
            println(box_line("$(DIM)GPU:    $(X) $(C)$(CFG.gpu_name)$(X) $(DIM)($(CFG.gpu_mem))$(X)"))
            println(box_sep())
            println(box_split("$(W)CPUs$(X)  $cpu_bar", "$(W)GPU$(X)   $gpu_bar"))
        else
            println(box_line("$(W)CPUs$(X)  $cpu_bar"))
        end
        println(box_split("$(W)Buffer$(X)  $(C)$(fmt_num(b_size))$(X)", "$(W)Internet$(X)  $inet_s"))
        println(box_split("$(W)Motor$(X)  $eng_s", "$(W)Formato$(X)  $fmt_s"))

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
    end

    if !isempty(subtitle)
        println(box_sep())
        println(box_line("  $(M)$(subtitle)$(X)"))
    end
    println(box_bot())
end

function splash()
    header("Iniciando Sistema")
    sleep(0.5)
end

"""
    print_found_key(addr, pub, priv, wif)
Exibe no console os detalhes da chave encontrada com formatação padronizada.
"""
function print_found_key(addr::String, pub::String, priv::String, wif::String)
    println("\n  🏆 $(G)$(BOLD)Chave encontrada!!$(X)")
    println("  $(W)Carteira:$(X)     $(G)$addr$(X)")
    println("  $(W)Public Key:$(X)   $(G)$pub$(X)")
    println("  $(W)Private Key:$(X)  $(G)$priv$(X)")
    println("  $(W)WIF:$(X)          $(G)$wif$(X)\n")
end

end # module
