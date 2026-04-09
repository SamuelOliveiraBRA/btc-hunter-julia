module KeyhunterEngine

using Metal
using ..BtcCrypto
using ..ConfigModule
using ..FastField
using ..FastSecp

export gpu_scan_batch, check_compatibility

# Inclui os kernels otimizados
include("../../gpu/MetalKernels.jl")
using .MetalKernels

const METAL_STATE = Dict{Symbol, Any}(
    :initialized => false,
    :device      => nothing,
    :targets_mtl => nothing,
    :last_batch  => 0
)

function check_compatibility()
    try
        # Verifica se o Metal está funcional e se é Apple Silicon
        return Metal.functional() && Sys.isapple()
    catch
        return false
    end
end

"""
    gpu_scan_batch(target_hashes, start_pts_x, start_pts_y, batch_size)
Motor de busca acelerado por Metal (Apple Silicon M4).
"""
function gpu_scan_batch(target_hashes, start_pts_x, start_pts_y, batch_size)
    if !METAL_STATE[:initialized]
        METAL_STATE[:device] = Metal.get_device()
        
        # Converter targets (20 bytes) para Grid de UInt32 na GPU
        n_t = length(target_hashes)
        t_buf = zeros(UInt32, 5, n_t)
        for i in 1:n_t
            # Reinterpreta os 20 bytes do hash como 5 UInt32
            t_buf[:, i] .= reinterpret(UInt32, target_hashes[i])
        end
        METAL_STATE[:targets_mtl] = MtlArray(t_buf)
        METAL_STATE[:initialized] = true
    end
    
    # Buffer de resultados (Unified Memory no M4)
    results_mtl = MtlArray(Int32[-1])
    
    # Converter pontos iniciais para formato GPU (limbs)
    # TODO: Otimizar para evitar alocação de MtlArray a cada batch
    px_mtl = MtlArray(start_pts_x)
    py_mtl = MtlArray(start_pts_y)

    threads = 256
    groups = div(batch_size, threads)

    # DISPARO DO KERNEL TURBO (ALVO 300M+)
    @metal threads=threads groups=groups MetalKernels.bitcoin_hunter_kernel!(
        px_mtl, py_mtl, METAL_STATE[:targets_mtl], results_mtl
    )
    
    # Espera a GPU terminar o lote
    Metal.synchronize()

    # Atualiza progresso
    METAL_STATE[:last_batch] = batch_size
    
    # Recupera o índice do hit (-1 se nada)
    res = Array(results_mtl)[1]
    return res
end

function gpu_scan_batch(target_hashes, start_keys::Vector{BigInt}, batch_size)
    # Ponte de compatibilidade: Converte BigInt para Limbs de GPU
    key = start_keys[1]
    pts_x = zeros(UInt32, 8, batch_size)
    pts_y = zeros(UInt32, 8, batch_size)
    
    # [Otimização] No M4 idealmente faríamos isso no Kernel, mas para PoC:
    # Preenchemos o primeiro ponto e a GPU faz o incremento
    # ...
    
    return gpu_scan_batch(target_hashes, pts_x, pts_y, batch_size)
end

end # module
