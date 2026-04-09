module MetalEngine

using Metal
using ..FastField
using ..FastSecp
using ..MultiTarget
using ..BtcCrypto

include("gpu/MetalKernels.jl")
using .MetalKernels

export GPUContext, scan_gpu!

"""
    GPUContext
Gerencia os buffers na memória da GPU Apple M4.
"""
struct GPUContext
    n::Int
    points_x::MtlArray{UInt32, 2} # [8, n] - 8 limbs de 32-bits
    points_y::MtlArray{UInt32, 2}
    targets::MtlArray{UInt32, 2}  # [5, n_targets] - 160 bits targets
    results::MtlArray{Int32, 1}   # [1] - Index do hit (-1 se nada)
    
    function GPUContext(n::Int, target_hashes::Vector{Vector{UInt8}})
        # Alocação na memória da GPU (HostShared para M4 Unified Memory)
        px = MtlArray{UInt32}(undef, (8, n))
        py = MtlArray{UInt32}(undef, (8, n))
        
        # Converter targets (20 bytes) para 5 x UInt32
        n_t = length(target_hashes)
        t_buf = zeros(UInt32, 5, n_t)
        for i in 1:n_t
            t_buf[:, i] .= reinterpret(UInt32, target_hashes[i])
        end
        mtl_targets = MtlArray(t_buf)
        
        res = MtlArray{Int32}(ones(Int32, 1) .* -1)
        
        new(n, px, py, mtl_targets, res)
    end
end

"""
    scan_gpu!(ctx, start_points, inc_point)
Dispara o pipeline Turbo na GPU. O CPU apenas monitora o buffer de resultados.
"""
function scan_gpu!(ctx::GPUContext, start_px, start_py, inc_px, inc_py)
    # Configuração de Grid massiva
    threads = 256
    groups = div(ctx.n, threads)
    
    # Reset no buffer de resultados
    ctx.results[1] = -1
    
    # Dispara o Big Bang
    @metal threads=threads groups=groups MetalKernels.bitcoin_hunter_kernel!(
        ctx.points_x, ctx.points_y, ctx.targets, ctx.results
    )
    
    synchronize()
    
    res_idx = Array(ctx.results)[1]
    return res_idx
end

end # module
