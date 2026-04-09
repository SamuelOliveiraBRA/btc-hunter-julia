
using Pkg
Pkg.activate(".")

include("src/FastField.jl")
include("src/FastSecp.jl")
include("src/BtcCrypto.jl")
include("src/SecpEngine.jl")
include("src/MultiTarget.jl")
include("src/engines/bitcrack/bitcrack_mac.jl")

using .FastField
using .BtcCrypto
using .MultiTarget
using .BitCrackEngine
using BenchmarkTools

function run_benchmark()
    println("--- Insetando Ambiente de Teste (Apple M4) ---")
    
    # 1. Mock de Alvos (1000 endereços)
    # Reutilizando um dos alvos do puzzle 30
    fake_addrs = ["1LHtnpd8nU5VHEMkG2TMYYNUjjLc992bps" for _ in 1:1000]
    # No MultiTarget real precisamos de um set de hashes Reais
    h160 = BtcCrypto.base58_to_hash160(fake_addrs[1])
    hashes = Set([h160])
    addr_map = Dict(h160 => fake_addrs[1])
    bf = MultiTarget.BloomFilter.load_massive_targets([h160])
    
    # Construir Filtro de Prefixo de 16-bit
    pf = falses(65536)
    idx = (UInt16(h160[1]) << 8) | UInt16(h160[2])
    pf[idx + 1] = true
    
    ts = MultiTarget.TargetSet(hashes, addr_map, bf, false, pf)
    
    # 2. Inicializar Motor (Batch 32k)
    batch_size = 32768
    start_key = BigInt(0x20000000)
    stride = BigInt(batch_size)
    state = BitCrackEngine.init_engine(start_key, ts, batch_size, stride, false)
    
    println("\n1. Medindo next_batch! (Matemática Secp256k1):")
    b_math = @benchmark BitCrackEngine.next_batch!($state)
    display(b_math)
    
    println("\n2. Medindo check_batch (Hashing + Filtros):")
    b_hashing = @benchmark BitCrackEngine.check_batch($state)
    display(b_hashing)
    
    # Cálculo de Performance (por core)
    # Medians are in nanoseconds
    t_math = median(b_math).time / 1e9 # segundos
    t_hash = median(b_hashing).time / 1e9 # segundos
    total_batch = t_math + t_hash
    keys_per_sec = batch_size / total_batch
    
    println("\n--- Resumo de Performance Teórica (1 Core) ---")
    println("Throughput: $(round(keys_per_sec/1000, digits=2))k keys/s")
    println("Projeção 4 Cores: $(round(4*keys_per_sec/1e6, digits=2)) M/s")
end

run_benchmark()
