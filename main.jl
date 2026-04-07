using Pkg; Pkg.activate(".")
# ═══════════════════════════════════════════════════════════
#  BTC KEY HUNTER  ·  Julia Edition  ·  v1.5.0
#  Arquitetura Modular & Performance Otimizada
# ═══════════════════════════════════════════════════════════

# ── Carregamento de módulos ───────────────────────────────
include("src/Config.jl")
using .ConfigModule

include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/BtcUtils.jl")
include("src/CheckpointManager.jl")
include("src/BloomFilter.jl")
include("src/MultiTarget.jl")

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

include("src/GpuCrypto.jl")
include("src/scanner/GpuScanner.jl")
using .GpuCrypto, .GpuScanner

include("src/UI.jl")
using .UIModule

include("src/scanner/ScannerOrchestrator.jl")
using .ScannerOrchestrator

include("src/Benchmark.jl")
using .BenchmarkModule

using HTTP, JSON, Random, Dates, Printf

# ── Utilitários Adicionais ───────────────────────────────
hex2big(s) = parse(BigInt, replace(strip(s), "0x" => "", "0X" => ""), base=16)
load_ranges() = JSON.parsefile("data/ranges.json")["ranges"]

function parse_cli_args()
    args = ARGS
    isempty(args) && return false
    
    ranges = load_ranges()
    p_num = 0
    mode = 1
    engine = CFG.engine
    p_start = 0.0; p_end = 100.0
    h_start = ""; h_end = ""
    use_hex = false

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--puzzle" && i < length(args)
            p_num = tryparse(Int, args[i+1])
            i += 1
        elseif arg == "--modo" && i < length(args)
            mode = tryparse(Int, args[i+1])
            i += 1
        elseif arg == "--motor" && i < length(args)
            engine = Symbol(args[i+1])
            i += 1
        elseif arg == "--porcentagem" && i < length(args)
            p_start = tryparse(Float64, args[i+1])
            i += 1
        elseif arg == "--fim" && i < length(args)
            p_end = tryparse(Float64, args[i+1])
            i += 1
        elseif arg == "--hstart" && i < length(args)
            h_start = args[i+1]
            use_hex = true
            i += 1
        elseif arg == "--hend" && i < length(args)
            h_end = args[i+1]
            use_hex = true
            i += 1
        elseif arg == "--internet"
            CFG.internet = true
        end
        i += 1
    end

    if p_num > 0 && p_num <= length(ranges)
        r = ranges[p_num]
        CFG.wallet_num = p_num
        CFG.wallet_addr = get(r, "endereco", "")
        CFG.interval_min = r["min"]
        CFG.interval_max = r["max"]
        CFG.engine = engine
        
        if CFG.internet
            CFG.saldo = BtcUtils.get_balance(CFG.wallet_addr)
        end
        
        r_min = hex2big(CFG.interval_min)
        r_max = hex2big(CFG.interval_max)
        r_size = r_max - r_min
        
        start_k = r_min
        end_k   = r_max

        if use_hex
            try
                !isempty(h_start) && (start_k = hex2big(h_start))
                !isempty(h_end) && (end_k = hex2big(h_end))
            catch; end
        else
            start_k = r_min + floor(BigInt, r_size * (p_start / 100.0))
            end_k   = r_min + floor(BigInt, r_size * (p_end / 100.0))
        end

        # Inicia direto sem menu
        if mode == 2 # Reverso
            scan_dashboard([CFG.wallet_addr], r_min, r_max, mode, end_k, start_k, puzzle_id=CFG.wallet_num)
        else
            scan_dashboard([CFG.wallet_addr], r_min, r_max, mode, start_k, end_k, puzzle_id=CFG.wallet_num)
        end
        return true
    end
    return false
end

# ── Menus Refatorados ─────────────────────────────────────

function escolher_cpus()
    n = Sys.CPU_THREADS
    while true
        header("Configuração › CPUs")
        println("  Detectadas: $(G)$n$(X) threads lógicas")
        println("  $(DIM)Julia threads ativos: $(Threads.nthreads())$(X)\n")
        s = UIModule.input("  $(W)Quantas CPUs usar?$(X) [1-$n]: ")
        v = tryparse(Int, strip(s))
        if !isnothing(v) && 1 <= v <= n
            CFG.cpus = v
            ConfigModule.save_settings(CFG)
            return
        end
        println("\n  $(R)● Valor inválido.$(X)")
        sleep(1)
    end
end

function habilitar_internet()
    header("Configuração › Internet")
    println("  Habilitar consulta de saldo via blockchain.info?\n")
    println("  $(G)[1]$(X)  Sim — consultar saldo")
    println("  $(R)[2]$(X)  Não — modo offline\n")
    while true
        op = UIModule.input("  Opção: ")
        if op == "1"
            CFG.internet = true
            ConfigModule.save_settings(CFG)
            return
        elseif op == "2"
            CFG.internet = false
            ConfigModule.save_settings(CFG)
            return
        end
        print("\r  $(R)Opção inválida.$(X)"); sleep(0.5)
    end
end


function escolher_carteira(ranges)
    page_size = 15; page = 1; total = length(ranges)
    while true
        header("Selecionar Puzzle")
        start_i = (page-1) * page_size + 1
        end_i   = min(page * page_size, total)

        for i in start_i:end_i
            r = ranges[i]
            st = r["status"] == 0 ? G*"✓"*X : R*"✗"*X
            addr = isempty(r["endereco"]) ? DIM*"(sem alvo)"*X : Y*r["endereco"][1:min(end,18)]*"..."*X
            println("  $(lpad(i, 3))  $st  $(DIM)$(rpad(r["min"][1:min(end,16)], 16))$(X)  $addr")
        end

        println("\n  $(B)[A]$(X) Ant  │  $(B)[P]$(X) Próx  │  $(W)[#]$(X) Escolher")
        s = strip(lowercase(UIModule.input("  Opção: ")))
        if s == "a" && page > 1; page -= 1
        elseif s == "p" && page < ceil(Int, total/page_size); page += 1
        else
            v = tryparse(Int, s)
            if !isnothing(v) && 1 <= v <= total
                r = ranges[v]
                CFG.wallet_num = v
                CFG.wallet_addr = get(r, "endereco", "")
                CFG.interval_min = r["min"]
                CFG.interval_max = r["max"]
                ConfigModule.save_settings(CFG)
                return
            end
        end
    end
end

function escolher_motor()
    header("Selecionar Motor")
    println("  $(W)Escolha o motor de busca padrão:$(X)\n")
    println("  $(G)[1]$(X)  Julia (SecpOpt)  $(DIM)- Estável, nativo$(X)")
    println("  $(Y)[2]$(X)  BitCrack        $(DIM)- Alta performance CPU$(X)")
    println("  $(B)[3]$(X)  Keyhunter (GPU) $(DIM)- Aceleração CUDA$(X)")
    println("  $(DIM)[0]  Voltar$(X)\n")
    
    m_op = UIModule.input("  Opção: ")
    if m_op == "1"; CFG.engine = :secp
    elseif m_op == "2"; CFG.engine = :bitcrack
    elseif m_op == "3"; CFG.engine = :gpu
    end
    ConfigModule.save_settings(CFG)
end

function config_menu()
    while true
        header("Configurações")
        println("  $(B)[1]$(X)  Configurar CPUs     $(DIM)($(CFG.cpus) cores)$(X)")
        println("  $(C)[2]$(X)  Configurar Internet $(DIM)($(CFG.internet ? "Ligada" : "Desligada"))$(X)")
        println("  $(M)[3]  Benchmark / Ajuste$(X)")
        println("  $(Y)[4]  Formato de Busca $(DIM)($(CFG.both_formats ? "Ambos" : "Comprimido"))$(X)")
        println("  $(DIM)[0]  Voltar$(X)\n")

        op = UIModule.input("  Opção: ")
        if op == "1"; escolher_cpus()
        elseif op == "2"; habilitar_internet()
        elseif op == "3"; run_benchmark()
        elseif op == "4"
            CFG.both_formats = !CFG.both_formats
            ConfigModule.save_settings(CFG)
        elseif op == "0"; break
        end
    end
end

# ── Menu Inicial e Loop ───────────────────────────────────

function pre_scan_menu()
    if CFG.wallet_num == 0
        println("  $(R)Selecione um puzzle primeiro (Opção 2).$(X)"); sleep(1.5); return
    end

    # ── Pergunta de Internet (Regra: Perguntar todas as vezes) ──
    header("Consulta de Saldo")
    println("  $(W)Deseja consultar o saldo da carteira na internet?$(X)\n")
    println("  $(G)[1]$(X)  Sim — consultar blockchain.info")
    println("  $(R)[2]$(X)  Não — modo offline\n")
    
    net_op = UIModule.input("  Opção: ")
    CFG.internet = (net_op == "1")
    if CFG.internet
        print("  $(Y)Consultando saldo...$(X)")
        CFG.saldo = BtcUtils.get_balance(CFG.wallet_addr)
        println("\r  $(W)Saldo encontrado:$(X) $(G)$(CFG.saldo) BTC$(X)    ")
        sleep(1)
    else
        CFG.saldo = ""
    end

    # ── Configurações de Intervalo ─────────────────────────
    header("Configuração de Busca")
    println("  $(W)Modo de Varredura:$(X)\n")
    println("  $(G)[1]$(X)  Sequencial →")
    println("  $(Y)[2]$(X)  Reverso    ←")
    println("  $(B)[3]$(X)  Aleatório  ⟳")
    println("  $(DIM)[0]  Cancelar$(X)\n")
    
    mode_op = UIModule.input("  Modo: ")
    mode = tryparse(Int, mode_op)
    (isnothing(mode) || mode < 1 || mode > 3) && return

    header("Configuração de Range")
    println("  $(W)Tipo de Intervalo:$(X)\n")
    println("  $(G)[1]$(X)  Range Completo ")
    println("  $(Y)[2]$(X)  Por Percentual ")
    println("  $(B)[3]$(X)  Hex Personalizado")
    println("  $(DIM)[0]  Cancelar$(X)\n")

    range_op = UIModule.input("  Opção: ")
    
    r_min = hex2big(CFG.interval_min)
    r_max = hex2big(CFG.interval_max)
    r_size = r_max - r_min
    
    start_k = r_min
    end_k   = r_max

    if range_op == "2" # Percentual
        s_start = UIModule.input("  $(W)Percentual Inicial$(X) [0.0 - 100.0]: ")
        p_start = tryparse(Float64, s_start) |> (v -> isnothing(v) ? 0.0 : clamp(v, 0.0, 100.0))
        s_end = UIModule.input("  $(W)Percentual Final$(X)   [$(p_start) - 100.0]: ")
        p_end = tryparse(Float64, s_end) |> (v -> isnothing(v) ? 100.0 : clamp(v, p_start, 100.0))
        
        start_k = r_min + floor(BigInt, r_size * (p_start / 100.0))
        end_k   = r_min + floor(BigInt, r_size * (p_end / 100.0))
        
    elseif range_op == "3" # Hex Personalizado
        h_start = UIModule.input("  $(W)Hex Inicial$(X): ")
        h_end   = UIModule.input("  $(W)Hex Final$(X):   ")
        try
            start_k = hex2big(h_start)
            end_k   = hex2big(h_end)
        catch
            println("  $(R)Erro no formato hexadecimal. Usando range padrão.$(X)"); sleep(1)
        end
    elseif range_op == "0"
        return
    end

    # ── Início do Scan ─────────────────────────────────────
    if mode == 2 # Reverso
        scan_dashboard([CFG.wallet_addr], r_min, r_max, mode, end_k, start_k, puzzle_id=CFG.wallet_num)
    else
        scan_dashboard([CFG.wallet_addr], r_min, r_max, mode, start_k, end_k, puzzle_id=CFG.wallet_num)
    end
end

function main_menu()
    ranges = load_ranges()
    while true
        header("Menu Principal")
        println("  $(G)[1]$(X)  Escolher motor de busca")
        println("  $(Y)[2]$(X)  Escolher Puzzle")
        println("  $(B)[3]$(X)  Iniciar Busca")
        println("  $(C)[4]$(X)  Configurações")
        println("  $(DIM)[0]  Sair$(X)")
        
        op = UIModule.input("\n  Opção: ")
        if op == "1"; escolher_motor()
        elseif op == "2"; escolher_carteira(ranges)
        elseif op == "3"; pre_scan_menu()
        elseif op == "4"; config_menu()
        elseif op == "0"; show_cursor(); exit(0)
        end
    end
end

# ── Start ─────────────────────────────────────────────────
function main()
    mkpath("outputs")
    
    # Tenta processar argumentos de linha de comando primeiro
    if parse_cli_args()
        return
    end

    # splash()  # Removido para evitar duplicidade, já que header() faz o trabalho
    main_menu()
end

main()
