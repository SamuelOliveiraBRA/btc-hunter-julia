# bench_runner.jl - Rodar de dentro de src/
module BenchRunner

include("Config.jl")
using .ConfigModule

include("BloomFilter.jl")
using .BloomFilter

include("FastField.jl")
using .FastField

include("FastSecp.jl")
using .FastSecp

include("BtcCrypto.jl")
using .BtcCrypto

include("CheckpointManager.jl")
using .CheckpointManager

include("Base58.jl")
using .Base58

include("BtcUtils.jl")
using .BtcUtils

include("SecpOptimized.jl")
using .SecpOptimized

include("GpuCrypto.jl")
using .GpuCrypto

include("MultiTarget.jl")
using .MultiTarget

include("engines/Engines.jl")
using .Engines

using Printf

function run_bench(threads=8, batch_sz=16384)
    println("--- BENCHMARK M4 OPTIMIZATION (BASELINE) ---")
    
    target_h160 = zeros(UInt8, 20)
    engine = Engines.init_engine("BitCrack", 1, BigInt(0x4000000000000000), BigInt(0x7fffffffffffffff), [target_h160])
    
    states = [Engines.BitCrackEngine.BitCrackState(engine, i) for i in 1:threads]
    stop_signal = Ref(false)
    keys_done = Threads.Atomic{Int64}(0)
    
    t_start = time()
    @sync for i in 1:threads
        Threads.@spawn begin
            state = states[i]
            local_count = 0
            while !stop_signal[]
                Engines.BitCrackEngine.next_batch!(state)
                Engines.BitCrackEngine.check_batch(state)
                local_count += batch_sz
                if local_count >= 100 * batch_sz
                    Threads.atomic_add!(keys_done, local_count)
                    local_count = 0
                end
            end
        end
    end
    
    sleep(5)
    stop_signal[] = true
    t_end = time()
    
    total_keys = keys_done[]
    duration = t_end - t_start
    kps = total_keys / duration
    @printf("\nRESULTADO BASELINE: %.2f M keys/s\n", kps / 1e6)
end

end # module

using .BenchRunner
BenchRunner.run_bench(min(Threads.nthreads(), 10), 16384)
