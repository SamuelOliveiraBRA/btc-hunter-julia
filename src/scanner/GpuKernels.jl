# GpuKernels.jl - Apenas para Linux/NVIDIA CUDA
# Este arquivo NÃO deve ser incluído no macOS

module GpuKernels

using CUDA
using ..GpuCrypto
using ..GpuHashing
using ..SecpOptimized

# Kernel Principal de Varredura PURA (Total GPU)
function scan_kernel_pure(points, jump_point, targets, found, steps)
    idx = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    
    if idx <= length(points)
        curr_p = points[idx]
        
        blocks_of_4 = div(steps, 4)
        leftover = steps % 4
        
        curr_step = 1
        for b in 1:blocks_of_4
            p1 = curr_p; curr_p = add_gpu_jacobian(curr_p, jump_point)
            p2 = curr_p; curr_p = add_gpu_jacobian(curr_p, jump_point)
            p3 = curr_p; curr_p = add_gpu_jacobian(curr_p, jump_point)
            p4 = curr_p; curr_p = add_gpu_jacobian(curr_p, jump_point)
            
            invs = batch_invert_4(p1.z, p2.z, p3.z, p4.z)
            
            gpu_check_p(p1, invs[1], targets, found, idx, curr_step); curr_step += 1
            gpu_check_p(p2, invs[2], targets, found, idx, curr_step); curr_step += 1
            gpu_check_p(p3, invs[3], targets, found, idx, curr_step); curr_step += 1
            gpu_check_p(p4, invs[4], targets, found, idx, curr_step); curr_step += 1
        end
        
        for l in 1:leftover
            invZ = invP_gpu(curr_p.z)
            gpu_check_p(curr_p, invZ, targets, found, idx, curr_step)
            curr_p = add_gpu_jacobian(curr_p, jump_point)
            curr_step += 1
        end
        
        points[idx] = curr_p
    end
    return nothing
end

end # module