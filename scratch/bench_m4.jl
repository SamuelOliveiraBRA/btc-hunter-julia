using Pkg; Pkg.activate(joinpath(@__DIR__, ".."))
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

include("../src/Config.jl")
include("../src/Base58.jl")
include("../src/BtcCrypto.jl")
include("../src/BtcUtils.jl")
include("../src/CheckpointManager.jl")
include("../src/PuzzleData.jl")
include("../src/BloomFilter.jl")
include("../src/MultiTarget.jl")
include("../src/SecpOptimized.jl")
include("../src/GpuCrypto.jl")
include("../src/FastField.jl")
include("../src/FastSecp.jl")
include("../src/engines/Engines.jl")

using .ConfigModule
using .Engines
using .BtcCrypto
using .MultiTarget
using Dates
using Printf

function bench_with_verification()
    println("=================================================================")
    println(" BENCHMARK + VERIFICAÇÃO DE CHAVE (Teste de Estabilidade)")
    println("=================================================================")
    
    # Carteira 20
    target_addr = "1HsMJxNiV7TLxmoF6uJNkydxPFDog4NQum"
    known_priv  = "00000000000000000000000000000000000000000000000000000000000d2c55"
    
    # Vamos iniciar exatamente 800 mil chaves antes para evitar start base negativo
    distance_keys = 800_000
    expected_hex_key = parse(BigInt, known_priv, base=16)
    start_key = expected_hex_key - distance_keys
    
    target_set = MultiTarget.build_target_set([target_addr], BtcCrypto.base58_to_hash160)
    
    batch_sz = 10_000
    stride = batch_sz
    
    println("→ Alvo:         ", target_addr)
    println("→ Start Key:    ", string(start_key, base=16))
    println("→ Expected Key: ", string(expected_hex_key, base=16))
    println("→ Distância:    $(distance_keys) chaves")
    println("\nIniciando Engine BitCrack (Batch = $batch_sz)...")
    
    state = Engines.BitCrackEngine.init_engine(start_key, target_set, batch_sz, stride, false)
    
    found = false
    found_idx = 0
    found_batch = 0
    
    max_batches = ceil(Int, distance_keys / batch_sz) + 10 # Sobra de garantia
    
    t_start = time()
    t_last = t_start
    total_processed = 0
    
    for b in 1:max_batches
        idx, h_f = Engines.BitCrackEngine.check_batch(state)
        if idx > 0
            found = true
            found_idx = idx
            found_batch = b
            break
        end
        total_processed += batch_sz
        Engines.BitCrackEngine.next_batch!(state)
        
        # Log a cada 50 batches
        if b % 50 == 0
            curr_t = time()
            elps = curr_t - t_last
            spd = (50 * batch_sz) / elps
            @printf("  Batch %4d | %d chaves | Speed: %.2f K/s\n", b, total_processed, spd/1000)
            t_last = curr_t
        end
    end
    t_end = time()
    elapsed = t_end - t_start
    
    println("\n=================================================================")
    if found
        actual_key = start_key + ((found_batch - 1) * batch_sz) + (found_idx - 1)
        println("✅ SUCESSO! CHAVE ENCONTRADA")
        println("Tempo Total : $(round(elapsed, digits=2)) s")
        println("Veloc. Média: $(round((total_processed + found_idx) / elapsed / 1000, digits=2)) K/s")
        if actual_key == expected_hex_key
            println("✅ CHAVE EXATA COMBINA: ", string(expected_hex_key, base=16))
        else
            println("❌ ERRO GRAVE! Hash bateu mas a chave deu: ", string(actual_key, base=16))
        end
    else
        println("❌ FALHA! Varreu $max_batches batches ($total_processed chaves) e NÃO ACHOU a chave.")
    end
    println("=================================================================")
end

bench_with_verification()
