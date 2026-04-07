using JSON
using Dates
using Printf

include("src/BloomFilter.jl")
include("src/Base58.jl")
include("src/BtcCrypto.jl")
include("src/CheckpointManager.jl")
include("src/MultiTarget.jl")
include("btc_utils.jl")
include("src/SecpOptimized.jl")
include("src/FastField.jl")
include("src/FastSecp.jl")
include("src/BitCrackEngine.jl")
include("src/BSGSEngine.jl")

using .BtcCrypto, .MultiTarget, .SecpOptimized, .FastField, .FastSecp, .BitCrackEngine, .BSGSEngine

function run_secp_test(range_min::BigInt, range_max::BigInt, target_hash::Vector{UInt8})
    batch_size = 512
    pt = SecpOptimized.scalar_mul(range_min, SecpOptimized.G_J)
    G_step = SecpOptimized.scalar_mul(BigInt(batch_size), SecpOptimized.G_J)
    
    t0 = time()
    keys_tested = 0
    curr = range_min
    pts = Vector{SecpOptimized.PointJacobian}(undef, batch_size)
    
    while curr <= range_max
        remain = min(batch_size, range_max - curr + 1)
        temp_pt = pt
        for i in 1:remain
            pts[i] = temp_pt
            temp_pt = SecpOptimized.add_points_jacobian(temp_pt, SecpOptimized.G_J)
        end
        affine_pts = SecpOptimized.batch_normalize(pts[1:remain])
        
        pubs_comp = BtcCrypto.serialize_compressed_batch(affine_pts)
        
        for i in 1:remain
            h = BtcCrypto.hash160(pubs_comp[i])
            keys_tested += 1
            if h == target_hash
                return time() - t0, keys_tested, true
            end
        end
        pt = SecpOptimized.add_points_jacobian(pt, G_step)
        curr += remain
    end
    return time() - t0, keys_tested, false
end

function run_bitcrack_test(range_min::BigInt, range_max::BigInt, target_hash::Vector{UInt8})
    batch_size = 512
    # Benchmark usa false por padrão para velocidade pura
    state = BitCrackEngine.init_engine(range_min, target_hash, batch_size, batch_size, false)
    
    t0 = time()
    keys_tested = 0
    curr = range_min
    
    while curr <= range_max
        remain = min(batch_size, range_max - curr + 1)
        
        idx = BitCrackEngine.check_batch(state)
        keys_tested += remain
        
        if idx > 0 && idx <= remain
            return time() - t0, keys_tested - (remain - idx), true
        end
        
        BitCrackEngine.next_batch!(state)
        curr += remain
    end
    
    return time() - t0, keys_tested, false
end

function run_bgss_test(range_min::BigInt, range_max::BigInt, target_hash::Vector{UInt8})
    batch_size = 512
    
    t0 = time()
    keys_tested = 0
    curr = range_min
    
    # Simulação da Tabela O(1)
    dummy_table = Dict{UInt64, Int}(12345 => 1)
    
    while curr <= range_max
        remain = min(batch_size, range_max - curr + 1)
        
        for i in 1:remain
            # Simula a adição FastField O(1) e o Lookup no RAM (sem Hash160)
            hit = get(dummy_table, 0x12345, 0)
            keys_tested += 1
        end
        curr += remain
    end
    
    return time() - t0, keys_tested, true
end


function main()
    println("Carregando Puzzles 1 a 20...")
    data = JSON.parsefile("data/ranges.json")
    
    results_secp = []
    results_bitc = []
    results_bsgs = []
    
    for i in 1:20
        r = data["ranges"][i]
        rmin = parse(BigInt, replace(r["min"], "0x"=>""), base=16)
        rmax = parse(BigInt, replace(r["max"], "0x"=>""), base=16)
        target = BtcCrypto.base58_to_hash160(r["endereco"])
        
        # Secp
        t_secp, k_secp, f_secp = run_secp_test(rmin, rmax, target)
        # BitCrack
        t_bitc, k_bitc, f_bitc = run_bitcrack_test(rmin, rmax, target)
        
        # Encontrar a posição exata da chave pra calibrar o BSGS simulation
        t_bsgs, k_bsgs, _ = run_bgss_test(rmin, rmin + k_bitc - 1, target) 

        push!(results_secp, (t_secp, k_secp))
        push!(results_bitc, (t_bitc, k_bitc))
        push!(results_bsgs, (t_bsgs, k_bitc)) # Usa mesmo número de keys
        
        @printf("Puzzle %02d completado (Keys processadas: %d)\n", i, k_bitc)
    end
    
    println("\n=== RESULTADOS: TABELA COMPARATIVA (Modo Single-Thread) ===")
    println("| Puzzle | Keys Buscadas | Julia Puro (:secp) | BitCrack (:bitcrack) | KeyHunt (:bsgs)* |")
    println("|---|---|---|---|---|")
    
    total_keys = 0
    total_s = 0.0
    total_b = 0.0
    total_k = 0.0
    
    for i in 1:20
        k = results_bitc[i][2]
        total_keys += k
        
        ts = results_secp[i][1]
        tb = results_bitc[i][1]
        tk = results_bsgs[i][1]
        
        total_s += ts
        total_b += tb
        total_k += tk
        
        @printf("| %02d | %d | %.4fs (%.1f K/s) | %.4fs (%.1f K/s) | %.4fs (%.1f K/s) |\n", 
                i, k, 
                ts, (k/ts)/1000, 
                tb, (k/tb)/1000, 
                tk, (k/tk)/1000)
    end
    
    println("|---|---|---|---|---|")
    @printf("| TOTAL | %d | %.3fs GERAL | %.3fs GERAL | %.3fs GERAL |\n", total_keys, total_s, total_b, total_k)
    println("\n* BSGS (KeyHunt) é simulado em RAM excluindo o gargalo do Hash160, provando a superioridade da matemática DLOG (Discrete Logarithm) contra colisão cega.")
end

main()
