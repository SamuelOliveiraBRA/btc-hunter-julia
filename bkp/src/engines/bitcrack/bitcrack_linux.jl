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
using ..SecpEngine
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

function init_engine(start_key::BigInt, targets::TargetSet, batch_size::Int, stride_size::Int, both_formats::Bool=false)::BitCrackState
    # 1. Calcular pontos iniciais em Jacobiana (bootstrap)
    points_j = Vector{PointJacobian}(undef, batch_size)
    curr_j = SecpEngine.scalar_mul(start_key, SecpEngine.G_J)
    step_j = SecpEngine.G_J
    
    for i in 1:batch_size
        points_j[i] = curr_j
        curr_j = SecpEngine.add_points_jacobian(curr_j, step_j)
    end
    
    # 2. Normalizar lote para Afim (uma única inversão pesada aqui)
    affine_tuples = SecpEngine.batch_normalize(points_j)
    points_a = [PointA(FE256(t[1]), FE256(t[2])) for t in affine_tuples]
    
    # 3. Preparar o Stride (S) em Afim
    stride_j = SecpEngine.scalar_mul(BigInt(stride_size), SecpEngine.G_J)
    sx, sy = SecpEngine.jacobian_to_affine(stride_j)
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
"""
    next_batch!(state)
Avança todos os pontos P[i] = P[i] + S usando Montgomery Batch Inversion.
Reduz drasticamente o número de multiplicações comparado a Jacobianas.
"""
function next_batch!(state::BitCrackState)
    n = state.batch_size
    Sx = state.stride_A.x
    Sy = state.stride_A.y
    
    # 1. Calcular Denominadores (dx) e Numeradores (dy)
    @inbounds for i in 1:n
        state.dx_buf[i] = sub_mod(Sx, state.points[i].x)
        state.dy_buf[i] = sub_mod(Sy, state.points[i].y)
    end
    
    # 2. Inversão em Lote dos Denominadores (Algoritmo de Montgomery)
    @inbounds state.prod_buf[1] = state.dx_buf[1]
    @inbounds for i in 2:n
        state.prod_buf[i] = mul_mod(state.prod_buf[i-1], state.dx_buf[i])
    end
    
    inv_all = inv_mod(state.prod_buf[n])
    
    curr_inv = inv_all
    @inbounds for i in n:-1:2
        state.inv_dx_buf[i] = mul_mod(curr_inv, state.prod_buf[i-1])
        curr_inv = mul_mod(curr_inv, state.dx_buf[i])
    end
    @inbounds state.inv_dx_buf[1] = curr_inv
    
    # 3. Adição de Pontos em coordenadas afins
    @inbounds for i in 1:n
        inv_dx = state.inv_dx_buf[i]
        dy     = state.dy_buf[i]
        Px     = state.points[i].x
        Py     = state.points[i].y
        
        # lambda = dy / dx
        lambda = mul_mod(dy, inv_dx)
        
        # x3 = lambda^2 - Px - Sx
        x3 = sub_mod(sub_mod(sqr_mod(lambda), Px), Sx)
        
        # y3 = lambda(Px - x3) - Py
        y3 = sub_mod(mul_mod(lambda, sub_mod(Px, x3)), Py)
        
        state.points[i] = PointA(x3, y3)
    end
end

# ── Verificar lote (Ultra-Fast: pontos já são afins) ──────
function check_batch(state::BitCrackState)::Tuple{Int, Vector{UInt8}}
    n = state.batch_size
    
    for i in 1:n
        @inbounds pt = state.points[i]
        
        # 1. Comprimido (C)
        # Coordenada X já é affine.x
        FastField.write_32bytes!(state.pub_buf, 2, pt.x)
        state.pub_buf[1] = iseven(pt.y) ? 0x02 : 0x03
        
        BtcCrypto.hash160!(view(state.pub_buf, 1:33), state.h160_buf, state.sha_buf)
        if check_hit(state.targets, state.h160_buf)
            return (i, copy(state.h160_buf))
        end

        # 2. Não-comprimido (U) - Opcional
        if state.both_formats
            state.pub_buf[1] = 0x04
            FastField.write_32bytes!(state.pub_buf, 34, pt.y)
            
            BtcCrypto.hash160!(view(state.pub_buf, 1:65), state.h160_buf, state.sha_buf)
            if check_hit(state.targets, state.h160_buf)
                return (i, copy(state.h160_buf))
            end
        end
    end

    return (0, UInt8[])
end

end # module
