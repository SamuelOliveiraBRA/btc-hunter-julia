module BitCrackEngine

# ═══════════════════════════════════════════════════════════════════
# BitCrackEngine.jl — Motor de varredura Afim em Lote (ALTA PERFORMANCE)
# Versão Otimizada: LINUX (Portabilidade M4 level)
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

# ── Avançar o lote (Batch Affine Addition 16x Unrolled) ─────
function next_batch!(state::BitCrackState)
    n = state.batch_size
    Sx = state.stride_A.x
    Sy = state.stride_A.y
    dx_buf = state.dx_buf
    dy_buf = state.dy_buf
    prod_buf = state.prod_buf
    inv_dx_buf = state.inv_dx_buf
    points = state.points
    
    # 1. Calcular Denominadores e Numeradores (Unrolled 16x)
    i = 1
    while i <= n - 15
        @inbounds @fastmath for j in 0:15
            idx = i + j
            dx_buf[idx] = sub_mod(Sx, points[idx].x)
            dy_buf[idx] = sub_mod(Sy, points[idx].y)
        end
        i += 16
    end
    while i <= n
        @inbounds begin
            dx_buf[i] = sub_mod(Sx, points[i].x)
            dy_buf[i] = sub_mod(Sy, points[i].y)
        end
        i += 1
    end
    
    # 2. Inversão em Lote (Montgomery)
    @inbounds prod_buf[1] = dx_buf[1]
    for i in 2:n
        @inbounds prod_buf[i] = mul_mod(prod_buf[i-1], dx_buf[i])
    end
    
    inv_all = inv_mod(prod_buf[n])
    
    curr_inv = inv_all
    for i in n:-1:2
        @inbounds inv_dx_buf[i] = mul_mod(curr_inv, prod_buf[i - 1])
        @inbounds curr_inv = mul_mod(curr_inv, dx_buf[i])
    end
    @inbounds inv_dx_buf[1] = curr_inv
    
    # 3. Adição de Pontos (Pipeline Interleaving 4x4)
    i = 1
    while i <= n - 15
        @inbounds begin
            for block in 0:3
                base = i + block * 4
                
                # Intercalar a primeira parte (Lambda) para 4 pontos
                lb1 = mul_mod(dy_buf[base],   inv_dx_buf[base])
                lb2 = mul_mod(dy_buf[base+1], inv_dx_buf[base+1])
                lb3 = mul_mod(dy_buf[base+2], inv_dx_buf[base+2])
                lb4 = mul_mod(dy_buf[base+3], inv_dx_buf[base+3])
                
                # Intercalar a segunda parte (X3, Y3)
                p1 = points[base]; p2 = points[base+1]; p3 = points[base+2]; p4 = points[base+3]
                
                x3_1 = sub_mod(sub_mod(sqr_mod(lb1), p1.x), Sx)
                x3_2 = sub_mod(sub_mod(sqr_mod(lb2), p2.x), Sx)
                x3_3 = sub_mod(sub_mod(sqr_mod(lb3), p3.x), Sx)
                x3_4 = sub_mod(sub_mod(sqr_mod(lb4), p4.x), Sx)
                
                y3_1 = sub_mod(mul_mod(lb1, sub_mod(p1.x, x3_1)), p1.y)
                y3_2 = sub_mod(mul_mod(lb2, sub_mod(p2.x, x3_2)), p2.y)
                y3_3 = sub_mod(mul_mod(lb3, sub_mod(p3.x, x3_3)), p3.y)
                y3_4 = sub_mod(mul_mod(lb4, sub_mod(p4.x, x3_4)), p4.y)
                
                points[base]   = PointA(x3_1, y3_1)
                points[base+1] = PointA(x3_2, y3_2)
                points[base+2] = PointA(x3_3, y3_3)
                points[base+3] = PointA(x3_4, y3_4)
            end
        end
        i += 16
    end
    # Resto
    while i <= n
        @inbounds begin
            inv_dx = inv_dx_buf[i]
            dy     = dy_buf[i]
            p      = points[i]
            lambda = mul_mod(dy, inv_dx)
            x3     = sub_mod(sub_mod(sqr_mod(lambda), p.x), Sx)
            y3     = sub_mod(mul_mod(lambda, sub_mod(p.x, x3)), p.y)
            points[i] = PointA(x3, y3)
        end
        i += 1
    end
end

# ── Verificar lote (Ultra-Fast: Unrolling 16x + Pointer Hashing) ─
function check_batch(state::BitCrackState)
    n = state.batch_size
    p_pub  = pointer(state.pub_buf)
    p_h160 = pointer(state.h160_buf)
    p_sha  = pointer(state.sha_buf)
    lut    = state.targets.lut
    points = state.points
    
    i = 1
    while i <= n - 15
        @inbounds for j in 0:15
            idx = i + j
            pt = points[idx]
            
            # 1. Comprimido
            unsafe_store!(p_pub, iseven(pt.y.v1) ? 0x02 : 0x03)
            FastField.write_32bytes!(state.pub_buf, 1, pt.x)
            
            # Hashing Nativo (libcrypto no Linux)
            BtcCrypto.hash160_ptr!(p_pub, 33, p_h160, p_sha)
            
            # Inlining Filtro LUT
            h1 = unsafe_load(p_h160, 1)
            h2 = unsafe_load(p_h160, 2)
            if lut[((Int(h1) << 8) | Int(h2)) + 1]
                if MultiTarget.check_hit(state.targets, state.h160_buf)
                    return (idx, copy(state.h160_buf))
                end
            end

            if state.both_formats
                unsafe_store!(p_pub, 0x04)
                FastField.write_32bytes!(state.pub_buf, 33, pt.y)
                BtcCrypto.hash160_ptr!(p_pub, 65, p_h160, p_sha)
                
                h1 = unsafe_load(p_h160, 1)
                h2 = unsafe_load(p_h160, 2)
                if lut[((Int(h1) << 8) | Int(h2)) + 1]
                    if MultiTarget.check_hit(state.targets, state.h160_buf)
                        return (idx, copy(state.h160_buf))
                    end
                end
            end
        end
        i += 16
    end

    while i <= n
        @inbounds begin
            pt = points[i]
            unsafe_store!(p_pub, iseven(pt.y.v1) ? 0x02 : 0x03)
            FastField.write_32bytes!(state.pub_buf, 1, pt.x)
            BtcCrypto.hash160_ptr!(p_pub, 33, p_h160, p_sha)
            
            h1 = unsafe_load(p_h160, 1)
            h2 = unsafe_load(p_h160, 2)
            if lut[((Int(h1) << 8) | Int(h2)) + 1]
                if MultiTarget.check_hit(state.targets, state.h160_buf)
                    return (i, copy(state.h160_buf))
                end
            end

            if state.both_formats
                unsafe_store!(p_pub, 0x04)
                FastField.write_32bytes!(state.pub_buf, 33, pt.y)
                BtcCrypto.hash160_ptr!(p_pub, 65, p_h160, p_sha)
                h1 = unsafe_load(p_h160, 1)
                h2 = unsafe_load(p_h160, 2)
                if lut[((Int(h1) << 8) | Int(h2)) + 1]
                    if MultiTarget.check_hit(state.targets, state.h160_buf)
                        return (i, copy(state.h160_buf))
                    end
                end
            end
        end
        i += 1
    end

    return (0, nothing)
end

end # module
