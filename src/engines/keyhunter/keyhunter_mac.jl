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

const GPU_STATE = Dict{Symbol, Any}(
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
    if !GPU_STATE[:initialized]
        GPU_STATE[:device] = Metal.device()
        
        # Converter targets (20 bytes) para Grid de UInt32 na GPU
        targets_vec = collect(target_hashes)
        n_t = length(targets_vec)
        t_buf = zeros(UInt32, 5, n_t)
        for i in 1:n_t
            # Reinterpreta os 20 bytes do hash como 5 UInt32
            t_buf[:, i] .= reinterpret(UInt32, targets_vec[i])
        end
        GPU_STATE[:targets_mtl] = MtlArray(t_buf)
        GPU_STATE[:initialized] = true
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
        px_mtl, py_mtl, GPU_STATE[:targets_mtl], results_mtl
    )
    
    # Espera a GPU terminar o lote
    Metal.synchronize()

    # Atualiza progresso
    GPU_STATE[:last_batch] = batch_size
    
    # Recupera o índice do hit (-1 se nada)
    res = Array(results_mtl)[1]
    return res
end

function gpu_scan_batch(target_hashes, start_keys::Vector{BigInt}, batch_size)
    # Ponte de compatibilidade: Converte BigInt para Limbs de GPU
    key = start_keys[1]
    
    # Deriva o ponto público inicial (X, Y) na CPU
    # No futuro, moveremos isso para o Kernel para ganhar milissegundos críticos
    pub_bytes = BtcCrypto.priv_to_pub_compressed(key)
    
    # Extrai o X (bytes 2-33)
    x_bytes = pub_bytes[2:33]
    pts_x = reshape(reinterpret(UInt32, x_bytes), 8, 1)
    pts_y = zeros(UInt32, 8, 1) # Placeholder: Para busca comprimida, Y não é crítico agora
    
    return gpu_scan_batch(target_hashes, pts_x, pts_y, batch_size)
end

end # module
