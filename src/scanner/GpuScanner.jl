module GpuScanner

if !Sys.isapple()
    using CUDA
end
using ..GpuCrypto
using ..BtcCrypto
using ..SecpOptimized
using ..ConfigModule: CFG

# A matemática Jacobiana agora é importada diretamente de GpuCrypto para evitar conflitos
# Os tipos usados são PointGpuJacobian e GpuUInt256

include("GpuHashing.jl")
using .GpuHashing

if !Sys.isapple()
    include("GpuKernels.jl")
    using .GpuKernels
    include("GpuRunner.jl")
    using .GpuRunner
end

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

# Cache de compatibilidade — verificado apenas uma vez por sessão
const _GPU_COMPAT = Ref{Union{Bool,Nothing}}(nothing)
const _GPU_COMPAT_MSG_SHOWN = Ref{Bool}(false)
const _CUDA_VERSION = Ref{VersionNumber}(v"0.0")
const _IS_BLACKWELL = Ref{Bool}(false)
const _SM_COUNT = Ref{Int}(0)
const _HAS_TMA = Ref{Bool}(false)
const _HAS_CLUSTERS = Ref{Bool}(false)

function check_compatibility()::Bool
    if !isnothing(_GPU_COMPAT[])
        return _GPU_COMPAT[]
    end
    
    if Sys.isapple()
        _GPU_COMPAT[] = false
        return false
    end
    
    try
        if !CUDA.functional()
            _GPU_COMPAT[] = false
            return false
        end
        dev = CUDA.device()
        cc = CUDA.capability(dev)
        major, minor = cc.major, cc.minor
        
        is_blackwell = (major == 12 && minor >= 0)
        is_supported = major >= 7 || is_blackwell
        
        if !is_supported
            if !_GPU_COMPAT_MSG_SHOWN[]
                @warn "GPU incompatível: Compute Capability $(major).$(minor) (mínimo: 7.0 ou 12.0+). Usando motor BitCrack."
                _GPU_COMPAT_MSG_SHOWN[] = true
                CFG.engine = :bitcrack
                CFG.gpu    = false
            end
            _GPU_COMPAT[] = false
            return false
        end
        
        cuda_ver = CUDA.version()
        _CUDA_VERSION[] = cuda_ver
        _IS_BLACKWELL[] = is_blackwell
        _SM_COUNT[] = CUDA.attribute(dev, CUDA.DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT)
        
        if is_blackwell && cuda_ver >= v"13.0"
            _HAS_TMA[] = true
            _HAS_CLUSTERS[] = true
            @info "Blackwell features habilitadas: TMA, Thread Block Clusters"
        end
        
        if is_blackwell && cuda_ver < v"13.0"
            @warn "Blackwell detectado (CC 12.x) mas CUDA toolkit $cuda_ver < 13.0. Features avançadas (TMA, Clusters) desabilitadas."
        elseif is_blackwell
            @info "RTX 50-series (Blackwell) detectada: CC $(major).$(minor), $(_SM_COUNT[]) SMs, CUDA $cuda_ver, TMA: $(_HAS_TMA[]), Clusters: $(_HAS_CLUSTERS[])"
        end
        
        _GPU_COMPAT[] = true
        return true
    catch e
        @warn "Erro ao verificar compatibilidade GPU: $e"
        _GPU_COMPAT[] = false
        return false
    end
end

# Feature flags para kernels otimizados
has_tma() = _HAS_TMA[]
has_clusters() = _HAS_CLUSTERS[]
is_blackwell() = _IS_BLACKWELL[]
cuda_version() = _CUDA_VERSION[]
sm_count() = _SM_COUNT[]

# Variáveis de estado persistentes para evitar realocações na VRAM
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
        v1 = UInt32(t[1]) | (UInt32(t[2])<<8) | (UInt32(t[3])<<16) | (UInt32(t[4])<<24)
        v2 = UInt32(t[5]) | (UInt32(t[6])<<8) | (UInt32(t[7])<<16) | (UInt32(t[8])<<24)
        v3 = UInt32(t[9]) | (UInt32(t[10])<<8) | (UInt32(t[11])<<16) | (UInt32(t[12])<<24)
        v4 = UInt32(t[13]) | (UInt32(t[14])<<8) | (UInt32(t[15])<<16) | (UInt32(t[16])<<24)
        v5 = UInt32(t[17]) | (UInt32(t[18])<<8) | (UInt32(t[19])<<16) | (UInt32(t[20])<<24)
        h_targets[i] = (v1, v2, v3, v4, v5)
    end
    if isempty(h_targets) push!(h_targets, (UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0))) end
    if Sys.isapple()
        return h_targets  # Return host array on macOS
    else
        return CUDA.CuArray(h_targets)
    end
end

# Stubs para macOS - retornam 0 (não encontrado) sem usar GPU
if Sys.isapple()
function gpu_scan_batch(targets_set::Set{Vector{UInt8}}, start_keys::Vector{BigInt}, gpu_batch::Int)
    @warn "GPU não disponível no macOS. Use engine :bitcrack ou :secp"
    return 0
end

function run_gpu_test(duration_secs::Int=10)::Float64
    @warn "GPU não disponível no macOS"
    return -1.0
end
end

end # module