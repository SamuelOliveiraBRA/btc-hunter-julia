module GpuScanner

using CUDA
using ..GpuCrypto
using ..BtcCrypto
using ..SecpOptimized
using ..ConfigModule: CFG

# A matemática Jacobiana agora é importada diretamente de GpuCrypto para evitar conflitos
# Os tipos usados são PointGpuJacobian e GpuUInt256

include("GpuHashing.jl")
using .GpuHashing

@inline function batch_invert_4(z1::GpuUInt256, z2::GpuUInt256, z3::GpuUInt256, z4::GpuUInt256)
    p1 = z1
    p2 = mul_gpu(p1, z2)
    p3 = mul_gpu(p2, z3)
    p4 = mul_gpu(p3, z4)
    
    inv_total = invP_gpu(p4)
    
    inv4 = mul_gpu(inv_total, p3)
    inv_total = mul_gpu(inv_total, z4)
    
    inv3 = mul_gpu(inv_total, p2)
    inv_total = mul_gpu(inv_total, z3)
    
    inv2 = mul_gpu(inv_total, p1)
    inv_total = mul_gpu(inv_total, z2)
    
    inv1 = inv_total
    
    return (inv1, inv2, inv3, inv4)
end

@noinline function gpu_check_p(p::PointGpuJacobian, invZ::GpuUInt256, targets, found, idx, step)
    invZ2 = mul_gpu(invZ, invZ)
    invZ3 = mul_gpu(invZ2, invZ)
    p_x = mul_gpu(p.x, invZ2)
    p_y = mul_gpu(p.y, invZ3)
    
    is_even = ((p_y.v1 & UInt64(1)) == 0)
    h_ripemd = hash160_gpu(p_x, is_even)
    
    num_targets = length(targets)
    for i in 1:num_targets
        expected_hash = targets[i]
        is_inf = (p.z.v1 == 0 && p.z.v2 == 0 && p.z.v3 == 0 && p.z.v4 == 0)
        if !is_inf && (h_ripemd[1] == expected_hash[1] && h_ripemd[2] == expected_hash[2] && 
                       h_ripemd[3] == expected_hash[3] && h_ripemd[4] == expected_hash[4] && h_ripemd[5] == expected_hash[5])
            found[1] = Int32(idx)
            found[2] = Int32(step)
        end
    end
end

# ── Kernel Principal de Varredura PURA (Total GPU) ────────
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

# Cache de compatibilidade — verificado apenas uma vez por sessão
const _GPU_COMPAT = Ref{Union{Bool,Nothing}}(nothing)
const _GPU_COMPAT_MSG_SHOWN = Ref{Bool}(false)

function check_compatibility()::Bool
    # Usa cache para não repetir a verificação a cada ciclo
    if !isnothing(_GPU_COMPAT[])
        return _GPU_COMPAT[]
    end
    try
        if !CUDA.functional()
            _GPU_COMPAT[] = false
            return false
        end
        # Verifica Compute Capability mínima (CUDA 13.0 exige >= 7.0)
        dev = CUDA.device()
        cc = CUDA.capability(dev)
        major = cc.major
        if major < 7
            if !_GPU_COMPAT_MSG_SHOWN[]
                @warn "GPU incompatível com CUDA 13.0: Compute Capability $(major).$(cc.minor) detectada (mínimo: 7.0). Usando motor SecpOpt."
                _GPU_COMPAT_MSG_SHOWN[] = true
                CFG.engine = :secp
                CFG.gpu    = false
            end
            _GPU_COMPAT[] = false
            return false
        end
        _GPU_COMPAT[] = true
        return true
    catch
        _GPU_COMPAT[] = false
        return false
    end
end

"""
    run_gpu_test(duration_secs)
Testa a performance bruta no modo GPU PURA.
"""
function run_gpu_test(duration_secs::Int=10)::Float64
    if !check_compatibility() return -1.0 end
    try
        threads = 256
        blocks = 32 # 8192 threads totais
        internal_steps = 1000
        
        d_found = CUDA.zeros(Int32, 2)
        d_points = CUDA.zeros(PointGpuJacobian, threads * blocks)
        d_targets = CUDA.zeros(GpuUInt256, 1)
        # Ponto de salto (Jump)
        jump = PointGpuJacobian(GpuUInt256(1,0,0,0), GpuUInt256(1,0,0,0), GpuUInt256(1,0,0,0))
        
        start_time = time()
        total_keys = 0
        
        while (time() - start_time) < duration_secs
            @cuda threads=threads blocks=blocks scan_kernel_pure(d_points, jump, d_targets, d_found, internal_steps)
            total_keys += (threads * blocks * internal_steps)
        end
        
        return total_keys / (time() - start_time)
    catch e
        return -2.0
    end
end

# Variáveis de estado persistentes para evitar realocações na VRAM (Causa comum de instabilidade)
const GPU_STATE = Dict{Symbol, Any}(
    :d_points => nothing,
    :d_found => nothing,
    :d_targets => nothing,
    :last_range => nothing
)

"""
    prepare_gpu_targets(targets_set)
Converte alvos para o formato da GPU.
"""
function prepare_gpu_targets(targets_set::Set{Vector{UInt8}})
    targets_vec = collect(targets_set)
    h_targets = Vector{NTuple{5, UInt32}}(undef, length(targets_vec))
    for i in 1:length(targets_vec)
        t = targets_vec[i]
        # Pega os 20 bytes em little endian e coloca em 5 UInt32
        v1 = UInt32(t[1]) | (UInt32(t[2])<<8) | (UInt32(t[3])<<16) | (UInt32(t[4])<<24)
        v2 = UInt32(t[5]) | (UInt32(t[6])<<8) | (UInt32(t[7])<<16) | (UInt32(t[8])<<24)
        v3 = UInt32(t[9]) | (UInt32(t[10])<<8) | (UInt32(t[11])<<16) | (UInt32(t[12])<<24)
        v4 = UInt32(t[13]) | (UInt32(t[14])<<8) | (UInt32(t[15])<<16) | (UInt32(t[16])<<24)
        v5 = UInt32(t[17]) | (UInt32(t[18])<<8) | (UInt32(t[19])<<16) | (UInt32(t[20])<<24)
        h_targets[i] = (v1, v2, v3, v4, v5)
    end
    if isempty(h_targets) push!(h_targets, (UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0))) end
    return CUDA.CuArray(h_targets)
end

"""
    gpu_scan_batch(targets_set, start_keys, gpu_batch)
Realiza a busca em modo GPU PURA (Non-Hybrid).
"""
function gpu_scan_batch(targets_set::Set{Vector{UInt8}}, start_keys::Vector{BigInt}, gpu_batch::Int)
    try
        # Fixar 8192 threads simultâneas. O internal_steps ditará quantas chaves cada thread pula
        threads = 256
        blocks = 32
        total_threads = threads * blocks
        internal_steps = max(1, div(gpu_batch, total_threads))
        actual_batch = total_threads * internal_steps
        
        expected_next = isnothing(GPU_STATE[:last_range]) ? BigInt(0) : GPU_STATE[:last_range] + BigInt(GPU_STATE[:last_batch])
        
        # 1. Boot Otimizado (Só calcula na CPU se houver quebra de sequência)
        if isnothing(GPU_STATE[:d_points]) || start_keys[1] != expected_next
            h_points = Vector{PointGpuJacobian}(undef, total_threads)
            raw_points = Vector{SecpOptimized.PointJacobian}(undef, total_threads)
            # Isso pode levar uns 3-5 segundos na PRIMEIRA inicialização 
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
        
        # 2. Ponto de Salto
        jump_val = BigInt(total_threads)
        pt_j = SecpOptimized.scalar_mul(jump_val, SecpOptimized.G_J)
        jx, jy = SecpOptimized.jacobian_to_affine(pt_j)
        d_jump = PointGpuJacobian(
            GpuUInt256(UInt64(jx & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((jx >> 192) & 0xFFFFFFFFFFFFFFFF)),
            GpuUInt256(UInt64(jy & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 64) & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 128) & 0xFFFFFFFFFFFFFFFF), UInt64((jy >> 192) & 0xFFFFFFFFFFFFFFFF)),
            GpuUInt256(1, 0, 0, 0)
        )
        
        # 3. Execução e Sincronização Crítica
        CUDA.fill!(d_found, Int32(0)) # Limpa descoberta anterior
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
        # Exibe o warning apenas uma vez, depois desativa GPU silenciosamente
        if !_GPU_COMPAT_MSG_SHOWN[]
            @warn "Erro no motor GPU: $(sprint(showerror, e))"
            _GPU_COMPAT_MSG_SHOWN[] = true
            _GPU_COMPAT[] = false
            CFG.engine = :secp
            CFG.gpu    = false
        end
        # Reset de estado
        GPU_STATE[:d_points] = nothing
        GPU_STATE[:d_found]  = nothing
        return -1  # Sinaliza fallback permanente
    end
end

end # module
