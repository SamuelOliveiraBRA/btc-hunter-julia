module BitCrackEngine

# ═══════════════════════════════════════════════════════════════════
# BitCrackEngine.jl — Motor de varredura Afim em Lote (ALTA PERFORMANCE)
#
# Evolução:
# 1. Julia nativo (Jacobianas) -> 14k/s
# 2. BigInt otimizado + Zero-GC -> 140k/s
# 3. Batch Affine Addition -> ALTO DESEMPENHO (Alvo: +300k/s)
# ═══════════════════════════════════════════════════════════════════

using ..FastField
using ..FastSecp
using ..BtcCrypto
using ..SecpOptimized
using ..MultiTarget

export BitCrackState, init_engine, next_batch!, check_batch

using .FastField: FE256, mul_mod, inv_mod, from_big, to_big, sqr_mod, sub_mod, add_mod

# ── Estado do motor ───────────────────────────────────────
struct BitCrackState
    points       :: Vector{PointA}
    stride_A     :: PointA    # Stride em coordenadas afins
    targets      :: TargetSet
    batch_size   :: Int
    both_formats :: Bool
    pub_buf      :: Vector{UInt8} 
    
    # Buffers para Batch Affine Addition (Zero-GC)
    dx_buf       :: Vector{FE256}
    dy_buf       :: Vector{FE256}
    prod_buf     :: Vector{FE256}
    inv_dx_buf   :: Vector{FE256}
    
    # Buffers para Hashing
    sha_buf      :: Vector{UInt8}
    h160_buf     :: Vector{UInt8}
end

function init_engine(start_key::BigInt, targets::TargetSet, batch_size::Int, stride_size::Integer, both_formats::Bool=false)::BitCrackState
    # 1. Calcular pontos iniciais em Jacobiana (bootstrap)
    points_j = Vector{PointJacobian}(undef, batch_size)
    curr_j = SecpOptimized.scalar_mul(start_key, SecpOptimized.G_J)
    step_j = SecpOptimized.G_J
    
    for i in 1:batch_size
        points_j[i] = curr_j
        curr_j = SecpOptimized.add_points_jacobian(curr_j, step_j)
    end
    
    # 2. Normalizar lote para Afim (uma única inversão pesada aqui)
    affine_tuples = SecpOptimized.batch_normalize(points_j)
    points_a = [PointA(FE256(t[1]), FE256(t[2])) for t in affine_tuples]
    
    # 3. Preparar o Stride (S) em Afim
    stride_j = SecpOptimized.scalar_mul(BigInt(stride_size), SecpOptimized.G_J)
    sx, sy = SecpOptimized.jacobian_to_affine(stride_j)
    stride_a = PointA(FE256(sx), FE256(sy))
    
    # buffers
    pub_buf = Vector{UInt8}(undef, 65)
    dx_buf = Vector{FE256}(undef, batch_size)
    dy_buf = Vector{FE256}(undef, batch_size)
    prod_buf = Vector{FE256}(undef, batch_size)
    inv_dx_buf = Vector{FE256}(undef, batch_size)
    sha_buf = Vector{UInt8}(undef, 32)
    h160_buf = Vector{UInt8}(undef, 20)

    return BitCrackState(
        points_a, stride_a, targets, batch_size, both_formats, pub_buf,
        dx_buf, dy_buf, prod_buf, inv_dx_buf, sha_buf, h160_buf
    )
end

# ── Avançar o lote (Batch Affine Addition) ────────────────
function next_batch!(state::BitCrackState)
    n = state.batch_size
    Sx = state.stride_A.x
    Sy = state.stride_A.y
    dx_buf = state.dx_buf
    dy_buf = state.dy_buf
    prod_buf = state.prod_buf
    inv_dx_buf = state.inv_dx_buf
    points = state.points
    
    # 1. Calcular Denominadores e Numeradores (SIMD-friendly)
    @inbounds @fastmath for i in 1:n
        dx_buf[i] = sub_mod(Sx, points[i].x)
        dy_buf[i] = sub_mod(Sy, points[i].y)
    end
    
    # 2. Inversão em Lote (Montgomery)
    @inbounds prod_buf[1] = dx_buf[1]
    for i in 2:n
        @inbounds prod_buf[i] = mul_mod(prod_buf[i-1], dx_buf[i])
    end
    
    inv_all = inv_mod(prod_buf[n])
    
    curr_inv = inv_all
    for i in n:-1:2
        @inbounds inv_dx_buf[i] = mul_mod(curr_inv, prod_buf[i-1])
        @inbounds curr_inv = mul_mod(curr_inv, dx_buf[i])
    end
    @inbounds inv_dx_buf[1] = curr_inv
    
    # 3. Adição de Pontos (Loop Unrolling 4x)
    @inbounds @fastmath for i in 1:4:n
        for j in 0:3
            idx = i + j
            inv_dx = inv_dx_buf[idx]
            dy     = dy_buf[idx]
            Px     = points[idx].x
            Py     = points[idx].y
            
            lambda = mul_mod(dy, inv_dx)
            x3 = sub_mod(sub_mod(sqr_mod(lambda), Px), Sx)
            y3 = sub_mod(mul_mod(lambda, sub_mod(Px, x3)), Py)
            points[idx] = PointA(x3, y3)
        end
    end
end

# ── Verificar lote (Ultra-Otimizado para M4) ──────────────
function check_batch(state::BitCrackState)
    n = state.batch_size
    p_pub  = pointer(state.pub_buf)
    p_h160 = pointer(state.h160_buf)
    p_sha  = pointer(state.sha_buf)
    lut    = state.targets.lut
    points = state.points
    
    # Processamento unrolled para melhor aproveitamento do pipeline do M4
    @inbounds for i in 1:n
        pt = points[i]
        
        # 1. Formato Comprimido
        unsafe_store!(p_pub, iseven(pt.y.v1) ? 0x02 : 0x03)
        FastField.write_32bytes!(state.pub_buf, 1, pt.x)
        
        # Hashing (A parte mais cara) - Agora turbinado com CommonCrypto
        BtcCrypto.hash160_ptr!(p_pub, 33, p_h160, p_sha)
        
        # ── Inlining Crítico do Filtro LUT ──
        # Evita chamada de função e check de endereços em 99.99% dos casos
        h1 = unsafe_load(p_h160, 1)
        h2 = unsafe_load(p_h160, 2)
        idx_lut = (Int(h1) << 8) | Int(h2)
        
        if lut[idx_lut + 1]
            # Se cair aqui, é um hit em potencial. Verificamos a fundo.
            if MultiTarget.check_hit(state.targets, state.h160_buf)
                return (i, copy(state.h160_buf))
            end
        end

        # 2. Formato Não-comprimido (Se ativo)
        if state.both_formats
            unsafe_store!(p_pub, 0x04)
            FastField.write_32bytes!(state.pub_buf, 33, pt.y)
            BtcCrypto.hash160_ptr!(p_pub, 65, p_h160, p_sha)
            
            h1 = unsafe_load(p_h160, 1)
            h2 = unsafe_load(p_h160, 2)
            idx_lut_u = (Int(h1) << 8) | Int(h2)
            
            if lut[idx_lut_u + 1]
                if MultiTarget.check_hit(state.targets, state.h160_buf)
                    return (i, copy(state.h160_buf))
                end
            end
        end
    end

    return (0, nothing)
end

end # module
