
using Pkg; Pkg.activate(".")
using Base.Threads: @threads, nthreads
using Printf

# Incluindo módulos do sistema para teste real
include("../src/FastField.jl")
include("../src/BtcCrypto_M4.jl")
using .FastField, .BtcCrypto_M4

# Mock de alvos (para medir velocidade sem busca real no BD)
const LUT = zeros(Bool, 65536)

function run_bench(iterations=200)
    batch_size = 32768
    num_threads = nthreads()
    
    # Pre-alloc buffers por thread
    padded_bufs = [zeros(UInt8, 256) for _ in 1:num_threads]
    sha_bufs    = [zeros(UInt8, 128) for _ in 1:num_threads]
    h160_bufs   = [zeros(UInt8, 20)  for _ in 1:num_threads]
    
    # Mock points
    points = [FastField.FE256(rand(UInt64), rand(UInt64), rand(UInt64), rand(UInt64)) for _ in 1:(batch_size * num_threads)]
    
    println("🚀 Iniciando Benchmark M4 Nitro Raw...")
    println("   CPUs: ", num_threads)
    println("   Batch: ", batch_size)
    println("   Total de Chaves por Iteração: ", batch_size * num_threads)
    println("-"^50)

    start_time = time()
    
    @threads for t in 1:num_threads
        p_pad = pointer(padded_bufs[t])
        p_sha = pointer(sha_bufs[t])
        p_h160 = pointer(h160_bufs[t])
        
        for _ in 1:iterations
            # Simulando o loop unrolled de 4 vias
            for i in 1:4:batch_size
                # 1. Preparar Format Bytes (X is already in point)
                unsafe_store!(p_pad, 0x02)
                FastField.write_32bytes!(padded_bufs[t], 1, points[i])
                
                unsafe_store!(p_pad + 64, 0x03)
                FastField.write_32bytes!(padded_bufs[t], 65, points[i+1])
                
                # 2. Hashing Hardware (SHA256)
                BtcCrypto_M4.sha256_block_m4!(p_sha, p_pad)
                BtcCrypto_M4.sha256_block_m4!(p_sha + 32, p_pad + 64)
                
                # 3. RIPEMD160 (Overhead de ccall)
                ccall((:RIPEMD160, "libcrypto"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, Csize_t, Ptr{UInt8}), p_sha, 32, p_h160)
                
                # 4. Check LUT (Simulado)
                if LUT[((Int(unsafe_load(p_h160,1)) << 8) | Int(unsafe_load(p_h160,2))) + 1]
                    # Hit simulado
                end
                
                # Repete para os outros 2... (Pipelining manual)
                unsafe_store!(p_pad + 128, 0x02)
                FastField.write_32bytes!(padded_bufs[t], 129, points[i+2])
                BtcCrypto_M4.sha256_block_m4!(p_sha + 64, p_pad + 128)
                ccall((:RIPEMD160, "libcrypto"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, Csize_t, Ptr{UInt8}), p_sha + 64, 32, p_h160)
                
                unsafe_store!(p_pad + 192, 0x03)
                FastField.write_32bytes!(padded_bufs[t], 193, points[i+3])
                BtcCrypto_M4.sha256_block_m4!(p_sha + 96, p_pad + 192)
                ccall((:RIPEMD160, "libcrypto"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, Csize_t, Ptr{UInt8}), p_sha + 96, 32, p_h160)
            end
        end
    end
    
    end_time = time()
    total_time = end_time - start_time
    total_keys = batch_size * num_threads * iterations
    keys_per_sec = total_keys / total_time
    
    @printf("Resultados:\n")
    @printf("⏱️  Tempo Total:  %.2f s\n", total_time)
    @printf("🔑 Total Chaves:  %.2f M\n", total_keys / 1e6)
    @printf("⚡ Velocidade:    %.2f M/s\n", keys_per_sec / 1e6)
    println("-"^50)
    
    if keys_per_sec > 25e6
        println("🔥 STATUS: META 25M/s ALCANÇADA!")
    else
        println("📈 STATUS: NECESSITA MAIS OTIMIZAÇÃO NO PIPELINE")
    end
end

run_bench()
