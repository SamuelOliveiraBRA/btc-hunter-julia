# GpuRunner.jl - Apenas para Linux/NVIDIA CUDA
# Funções que usam @cuda macro

module GpuRunner

using CUDA
using ..GpuKernels: scan_kernel_pure
using ..GpuCrypto
using ..SecpOptimized
using ..ConfigModule: CFG

"""
    run_gpu_test(duration_secs)
Testa a performance bruta no modo GPU PURA.
"""
function run_gpu_test(duration_secs::Int=10)::Float64
    if !check_compatibility() return -1.0 end
    try
        dev = CUDA.device()
        sm_count = _SM_COUNT[] > 0 ? _SM_COUNT[] : CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)
        vram_bytes = try
            CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_TOTAL_GLOBAL_MEM)
        catch
            try
                CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_TOTAL_GLOBAL_MEMORY)
            catch
                32 * 1024^3
            end
        end
        vram_mb = vram_bytes ÷ (1024^2)
        
        threads = 256
        base_blocks_per_sm = _IS_BLACKWELL[] ? 8 : 4
        blocks = sm_count * base_blocks_per_sm
        max_threads_by_vram = (vram_mb * 1024 * 1024) ÷ (48 * 4)
        max_blocks_by_vram = max_threads_by_vram ÷ threads
        blocks = min(blocks, max_blocks_by_vram)
        blocks = max(blocks, 32)
        
        internal_steps = 1000
        
        d_found = CUDA.zeros(Int32, 2)
        d_points = CUDA.zeros(PointGpuJacobian, threads * blocks)
        d_targets = CUDA.zeros(GpuUInt256, 1)
        jump = PointGpuJacobian(GpuUInt256(1,0,0,0), GpuUInt256(1,0,0,0), GpuUInt256(1,0,0,0))
        
        start_time = time()
        total_keys = 0
        
        while (time() - start_time) < duration_secs
            @cuda threads=threads blocks=blocks scan_kernel_pure(d_points, jump, d_targets, d_found, internal_steps)
            total_keys += (threads * blocks * internal_steps)
        end
        
        return total_keys / (time() - start_time)
    catch e
        @warn "Erro no teste GPU: $e"
        return -2.0
    end
end

"""
    gpu_scan_batch(targets_set, start_keys, gpu_batch)
Realiza a busca em modo GPU PURA (Non-Hybrid).
"""
function gpu_scan_batch(targets_set::Set{Vector{UInt8}}, start_keys::Vector{BigInt}, gpu_batch::Int)
    try
        dev = CUDA.device()
        sm_count = _SM_COUNT[] > 0 ? _SM_COUNT[] : CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)
        vram_bytes = try
            CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_TOTAL_GLOBAL_MEM)
        catch
            try
                CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_TOTAL_GLOBAL_MEMORY)
            catch
                32 * 1024^3
            end
        end
        vram_mb = vram_bytes ÷ (1024^2)
        
        threads = 256
        base_blocks_per_sm = _IS_BLACKWELL[] ? 8 : 4
        blocks = sm_count * base_blocks_per_sm
        max_threads_by_vram = (vram_mb * 1024 * 1024) ÷ (48 * 4)
        max_blocks_by_vram = max_threads_by_vram ÷ threads
        blocks = min(blocks, max_blocks_by_vram)
        blocks = max(blocks, 32)
        
        total_threads = threads * blocks
        min_keys_per_launch = 1_000_000
        internal_steps = max(1, div(max(gpu_batch, min_keys_per_launch), total_threads))
        actual_batch = total_threads * internal_steps
        
        @info "GPU config: $(threads) threads × $(blocks) blocks = $(total_threads) threads, $(internal_steps) steps/thread = $(actual_batch) keys/launch, VRAM: $(vram_mb)MB, SMs: $(sm_count)"
        
        expected_next = isnothing(GPU_STATE[:last_range]) ? BigInt(0) : GPU_STATE[:last_range] + BigInt(GPU_STATE[:last_batch])
        
        if isnothing(GPU_STATE[:d_points]) || start_keys[1] != expected_next
            h_points = Vector{PointGpuJacobian}(undef, total_threads)
            raw_points = Vector{SecpOptimized.PointJacobian}(undef, total_threads)
            for i in 1:total_threads
                k = start_keys[1] + BigInt(i - 1)
                raw_points[i] = SecpOptimized.scalar_mul(k, SecpOptimized.G_J)
            end
            
            affines = SecpOptimized.batch_normalize(raw_points)
            
            for i in 1:total_threads
                ax, ay = affines[i]
                h_points[i] = PointGpuJacobian(
                    GpuUInt256(UInt64(ax & 0xFFFFFFFFFFFFFFFF), UInt64((ax >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((ax >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((ax >> 192) & 0xFFFFFFFFFFFFFFFF)),
                    GpuUInt256(UInt64(ay & 0xFFFFFFFFFFFFFFFF), UInt64((ay >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((ay >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((ay >> 192) & 0xFFFFFFFFFFFFFFFF)),
                    GpuUInt256(1, 0, 0, 0)
                )
            end
            if isnothing(GPU_STATE[:d_points])
                GPU_STATE[:d_points] = CUDA.CuArray(h_points)
                GPU_STATE[:d_targets] = prepare_gpu_targets(targets_set)
                GPU_STATE[:d_found] = CUDA.zeros(Int32, 2)
            else
                copyto!(GPU_STATE[:d_points], h_points)
                CUDA.unsafe_free!(GPU_STATE[:d_targets])
                GPU_STATE[:d_targets] = prepare_gpu_targets(targets_set)
            end
        end
        GPU_STATE[:last_range] = start_keys[1]
        GPU_STATE[:last_batch] = actual_batch
        
        d_points = GPU_STATE[:d_points]
        d_targets = GPU_STATE[:d_targets]
        d_found = GPU_STATE[:d_found]
        
        jump_val = BigInt(total_threads)
        pt_j = SecpOptimized.scalar_mul(jump_val, SecpOptimized.G_J)
        jx, jy = SecpOptimized.jacobian_to_affine(pt_j)
        d_jump = PointGpuJacobian(
            GpuUInt256(UInt64(jx & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 192) & 0xFFFFFFFFFFFFFFFF)),
            GpuUInt256(UInt64(jy & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 192) & 0xFFFFFFFFFFFFFFFF)),
            GpuUInt256(1, 0, 0, 0)
        )
        
        CUDA.fill!(d_found, Int32(0))
        @cuda threads=threads blocks=blocks scan_kernel_pure(d_points, d_jump, d_targets, d_found, internal_steps)
        CUDA.synchronize()
        
        found_data = Array(d_found)
        if found_data[1] > 0
            idx_thread = found_data[1]
            idx_step = found_data[2]
            offset = (idx_thread - 1) + (idx_step - 1) * total_threads
            return Int(offset + 1)
        end
        
        return 0
    catch e
        if !_GPU_COMPAT_MSG_SHOWN[]
            @warn "Erro no motor GPU: $(sprint(showerror, e))"
            _GPU_COMPAT_MSG_SHOWN[] = true
            _GPU_COMPAT[] = false
            CFG.engine = :bitcrack
            CFG.gpu    = false
        end
        GPU_STATE[:d_points] = nothing
        GPU_STATE[:d_found]  = nothing
        return -1
    end
end

end # module