module BitCrackEngine

# ═══════════════════════════════════════════════════════════════════
# BitCrackEngine.jl — Motor de varredura estilo BitCrack
#
# Implementa a lógica de varredura em lote com:
# - PointJ (coordenadas Jacobianas tipadas com FE256)
# - Stride incremental: avança todos os pontos sem scalar_mul
# - Batch inversion (Montgomery): uma inversão para N pontos
# - hash160_compressed_fast: serialização direta sem alocações extras
# ═══════════════════════════════════════════════════════════════════

using ..FastField
using ..FastSecp
using ..BtcCrypto
using ..SecpOptimized

export BitCrackState, init_engine, next_batch!, check_batch

# Importações explícitas do FastField para uso interno
import Base: ==

using .FastField: FE256, mul_mod, inv_mod, from_big, to_big, sqr_mod, sub_mod, add_mod

# ── Estado do motor ───────────────────────────────────────
"""
    BitCrackState
Estado do motor BitCrack para um worker.
- `points`: lote atual de pontos Jacobianos (avança via `next_batch!`)
- `stride_J`: ponto equivalente a `batch_size * G` (salto entre lotes)
- `target_hash`: Hash160 do endereço alvo (20 bytes)
- `batch_size`: número de chaves no lote
"""
struct BitCrackState
    points      :: Vector{PointJ}
    stride_J    :: PointJ
    target_hash :: Vector{UInt8}
    batch_size  :: Int
    both_formats :: Bool
    pub_buf     :: Vector{UInt8} # Buffer para serialização (C=33, U=65)
end

# ── Inicializar o motor ───────────────────────────────────
"""
    init_engine(start_key, target_hash, batch_size, stride_size, both_formats)
Inicializa o motor BitCrack a partir de uma chave privada de início.
Gera o lote inicial: P[i] = (start_key + i) * G via adição incremental.
"""
function init_engine(start_key::BigInt, target_hash::Vector{UInt8}, batch_size::Int, stride_size::Int, both_formats::Bool=false)::BitCrackState
    points = Vector{PointJ}(undef, batch_size)

    # Ponto base: start_key * G (usa SecpOptimized para bootstrap)
    base_p = _big_to_pointJ(start_key)

    # Gerar lote: P[i] = P[i-1] + G
    curr = base_p
    for i in 1:batch_size
        points[i] = curr
        curr = point_add_jacobian(curr, G_J_fast)
    end

    # Stride = stride_size * G (avança o salto total das threads de uma vez)
    stride_J = _big_to_pointJ(BigInt(stride_size))

    # Buffer reservado para serialização (33 bytes para C, 65 bytes para U)
    pub_buf = Vector{UInt8}(undef, 65)

    return BitCrackState(points, stride_J, target_hash, batch_size, both_formats, pub_buf)
end

# ── Avançar o lote ────────────────────────────────────────
"""
    next_batch!(state)
Avança todos os pontos em `stride_J` (= stride_size * G).
O(batch_size) adições de ponto — sem nenhuma scalar_mul.
"""
function next_batch!(state::BitCrackState)
    for i in 1:state.batch_size
        state.points[i] = point_add_jacobian(state.points[i], state.stride_J)
    end
end

# ── Verificar lote (batch inversion) ─────────────────────
"""
    check_batch(state) → Int
Verifica todos os pontos do lote usando uma única inversão modular
(algoritmo de Montgomery). Retorna o índice relativo no lote (1-based)
se encontrar a chave, ou 0 se não encontrar.
"""
function check_batch(state::BitCrackState)::Int
    n  = state.batch_size
    zs = [p.z for p in state.points]

    # ── Pré-produto acumulado ─────────────────────────────
    prod = Vector{FE256}(undef, n)
    prod[1] = zs[1]
    for i in 2:n
        prod[i] = mul_mod(prod[i-1], zs[i])
    end

    # ── Uma única inversão modular pesada ─────────────────
    inv_all = inv_mod(prod[n])

    # ── Reconstruir inversões individuais ─────────────────
    inv_zs = Vector{FE256}(undef, n)
    curr_inv = inv_all
    for i in n:-1:2
        inv_zs[i] = mul_mod(curr_inv, prod[i-1])
        curr_inv  = mul_mod(curr_inv, zs[i])
    end
    inv_zs[1] = curr_inv

    # ── Verificar cada ponto ──────────────────────────────
    for i in 1:n
        iz  = inv_zs[i]
        iz2 = mul_mod(iz, iz)
        iz3 = mul_mod(iz, iz2)

        # Coordenadas afins
        ax  = mul_mod(state.points[i].x, iz2)
        ay  = mul_mod(state.points[i].y, iz3)
        
        # 1. Comprimido (C)
        BtcCrypto.big_to_32bytes!(to_big(ax), state.pub_buf, 2)
        state.pub_buf[1] = iseven(to_big(ay)) ? 0x02 : 0x03
        
        h_c = BtcCrypto.hash160(view(state.pub_buf, 1:33))
        h_c == state.target_hash && return i

        # 2. Não-comprimido (U) - Opcional
        if state.both_formats
            # Já temos o prefixo na pos 1 e X na pos 2..33. 
            # Basta colocar Y na pos 34..65 e mudar prefixo para 0x04.
            state.pub_buf[1] = 0x04
            BtcCrypto.big_to_32bytes!(to_big(ay), state.pub_buf, 34)
            
            h_u = BtcCrypto.hash160(view(state.pub_buf, 1:65))
            h_u == state.target_hash && return i
        end
    end

    return 0
end

# ── Helpers internos ──────────────────────────────────────

"""
Converte um escalar BigInt para PointJ usando SecpOptimized como bootstrap.
Necessário apenas na inicialização de cada worker (O(log k) — uma única vez).
"""
function _big_to_pointJ(k::BigInt)::PointJ
    p = SecpOptimized.scalar_mul(k, SecpOptimized.G_J)
    return PointJ(
        from_big(p.X),
        from_big(p.Y),
        from_big(p.Z)
    )
end


end # module BitCrackEngine
