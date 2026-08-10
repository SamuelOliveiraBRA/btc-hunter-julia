module BitCrackEngine

# ═══════════════════════════════════════════════════════════════════
# BitCrackEngine.jl — Motor de varredura Afim em Lote (ALTA PERFORMANCE)
#
# Evolução:
# 1. Julia nativo (Jacobianas) -> 14k/s
# 2. BigInt otimizado + Zero-GC -> 140k/s
# 3. Batch Affine Addition -> ALTO DESEMPENHO (Alvo: +300k/s)
# 4. RIPEMD-160 Nativo + inv_mod Zero-GC (Alvo: 40-80M chaves/s)
# ═══════════════════════════════════════════════════════════════════

using ..FastField
using ..FastSecp
using ..SecpOptimized
using ..BtcCrypto
using ..MultiTarget
using ..FastRipemd
using ..BtcCrypto_M4

export BitCrackState, init_engine, next_batch!, check_batch

using .FastField: FE256, mul_mod, inv_mod, from_big, to_big, sqr_mod, sub_mod, add_mod

# ── Estado do motor ───────────────────────────────────────
struct BitCrackState
    points       :: Vector{PointA}
    stride_A     :: PointA    # Stride em coordenadas afins
    targets      :: TargetSet
    batch_size   :: Int
    compressed   :: Bool
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
    padded_buf   :: Vector{UInt8} # 256 bytes (4 blocos de 64 para hardware hashing)

    # Buffers temporários para saltos random (Zero-GC)
    temp_j_points :: Vector{PointJacobian}
end

function init_engine(start_key::BigInt, targets::TargetSet, batch_size::Int, stride_size::Integer, both_formats::Bool=false, is_reverse::Bool=false)::BitCrackState
    compressed = true
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
    if is_reverse
        stride_j = SecpOptimized.negate_point_jacobian(stride_j)
    end
    sx, sy = SecpOptimized.jacobian_to_affine(stride_j)
    stride_a = PointA(FE256(sx), FE256(sy))
    
    # buffers
    pub_buf = Vector{UInt8}(undef, 65)
    dx_buf = Vector{FE256}(undef, batch_size)
    dy_buf = Vector{FE256}(undef, batch_size)
    prod_buf = Vector{FE256}(undef, batch_size)
    inv_dx_buf = Vector{FE256}(undef, batch_size)
    sha_buf = Vector{UInt8}(undef, 128) # 4 resultados de 32 bytes
    h160_buf = Vector{UInt8}(undef, 80) # 4 resultados de 20 bytes
    padded_buf = zeros(UInt8, 256) # 4 blocos de 64 bytes
    for b in 0:3
        off = b * 64
        # SHA256 padding para 33 bytes (1 prefixo + 32 X):
        # byte 34 = 0x80, bytes 35-56 = zeros (22 bytes), 
        # bytes 57-64 = length 264 bits = 0x0000000000000108 (big-endian)
        padded_buf[off + 34] = 0x80
        padded_buf[off + 63] = 0x01
        padded_buf[off + 64] = 0x08
    end

    # Buffers temporários
    temp_j_points = Vector{PointJacobian}(undef, batch_size)

    return BitCrackState(
        points_a, stride_a, targets,        batch_size,
        compressed,
        both_formats,
        pub_buf,
        dx_buf,
        dy_buf, prod_buf, inv_dx_buf, sha_buf, h160_buf, padded_buf,
        temp_j_points
    )
end

# ── Re-inicializar Pontos (Sem Alocação) ──────────────────
function reinit_engine!(state::BitCrackState, start_key::BigInt)
    # 1. Calcular pontos iniciais em Jacobiana (bootstrap) usando buffer pré-alocado
    points_j = state.temp_j_points
    curr_j = SecpOptimized.scalar_mul(start_key, SecpOptimized.G_J)
    step_j = SecpOptimized.G_J
    
    for i in 1:state.batch_size
        @inbounds points_j[i] = curr_j
        curr_j = SecpOptimized.add_points_jacobian(curr_j, step_j)
    end
    
    # 2. Normalizar lote e atualizar o vetor 'points' do estado existente
    affine_tuples = SecpOptimized.batch_normalize(points_j)
    for i in 1:state.batch_size
        # Atualizamos o conteúdo do vetor existente para evitar alocações de buffer
        @inbounds state.points[i] = PointA(FE256(affine_tuples[i][1]), FE256(affine_tuples[i][2]))
    end
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
    
    # 1. Calcular Denominadores e Numeradores (Unrolled 16x)
    i = 1
    while i <= n - 15
        @inbounds for j in 0:15
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
        @inbounds inv_dx_buf[i] = mul_mod(curr_inv, prod_buf[i-1])
        @inbounds curr_inv = mul_mod(curr_inv, dx_buf[i])
    end
    @inbounds inv_dx_buf[1] = curr_inv
    
    # 3. Adição de Pontos (Pipeline Interleaving 4x4 para M4)
    # Processamos blocos de 16 pontos, intercalando as operações matemáticas 
    # para permitir que a CPU execute múltiplas multiplicações em paralelo.
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

# ── Verificar lote (Ultra-Otimizado para M4) ──────────────
function check_batch(state::BitCrackState)
    n = state.batch_size
    p_pub  = pointer(state.pub_buf)
    p_h160 = pointer(state.h160_buf)
    p_sha  = pointer(state.sha_buf)
    lut    = state.targets.lut
    points = state.points
    is_comp = state.compressed
    msg_len = is_comp ? 33 : 65
    
    # 1. Processamento unrolled com Pipelining de 4 vias
    i = 1
    p_pad = pointer(state.padded_buf)
    
    while i <= n - 3
        @inbounds begin
            # Carregar pontos
            pt1 = points[i];   pt2 = points[i+1]
            pt3 = points[i+2]; pt4 = points[i+3]
            
            # Hashing Batch 1 a 4 com SHA256 M4 Zero-GC
            if is_comp
                # Batch 1
                unsafe_store!(p_pad, iseven(pt1.y.v1) ? 0x02 : 0x03, 1)
                FastField.write_32bytes!(state.padded_buf, 1, pt1.x)
                BtcCrypto_M4.sha256_block_m4!(p_sha, p_pad)
                
                # Batch 2
                unsafe_store!(p_pad + 64, iseven(pt2.y.v1) ? 0x02 : 0x03, 1)
                FastField.write_32bytes!(state.padded_buf, 65, pt2.x)
                BtcCrypto_M4.sha256_block_m4!(p_sha + 32, p_pad + 64)
                
                # Batch 3
                unsafe_store!(p_pad + 128, iseven(pt3.y.v1) ? 0x02 : 0x03, 1)
                FastField.write_32bytes!(state.padded_buf, 129, pt3.x)
                BtcCrypto_M4.sha256_block_m4!(p_sha + 64, p_pad + 128)
                
                # Batch 4
                unsafe_store!(p_pad + 192, iseven(pt4.y.v1) ? 0x02 : 0x03, 1)
                FastField.write_32bytes!(state.padded_buf, 193, pt4.x)
                BtcCrypto_M4.sha256_block_m4!(p_sha + 96, p_pad + 192)
            else
                # Batch 1
                unsafe_store!(p_pub, 0x04, 1)
                FastField.write_32bytes!(state.pub_buf, 1, pt1.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt1.y)
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha)
                
                # Batch 2
                FastField.write_32bytes!(state.pub_buf, 1, pt2.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt2.y)
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha + 32)
                
                # Batch 3
                FastField.write_32bytes!(state.pub_buf, 1, pt3.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt3.y)
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha + 64)
                
                # Batch 4
                FastField.write_32bytes!(state.pub_buf, 1, pt4.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt4.y)
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha + 96)
            end

            # RIPEMD-160 de 4 vias (Zero-GC)
            FastRipemd.ripemd160_32b_4x!(p_sha, p_h160)

            if lut[((Int(unsafe_load(p_h160, 1)) << 8) | Int(unsafe_load(p_h160, 2))) + 1]
                # Criar Vector próprio para lookup no HashSet (evita problemas de hash no view)
                h160_slice = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160, 20, own=false))
                if h160_slice in state.targets.hashes
                    return (i, copy(h160_slice))
                end
            end

            if lut[((Int(unsafe_load(p_h160 + 20, 1)) << 8) | Int(unsafe_load(p_h160 + 20, 2))) + 1]
                h160_slice = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160 + 20, 20, own=false))
                if h160_slice in state.targets.hashes
                    return (i + 1, copy(h160_slice))
                end
            end

            if lut[((Int(unsafe_load(p_h160 + 40, 1)) << 8) | Int(unsafe_load(p_h160 + 40, 2))) + 1]
                h160_slice = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160 + 40, 20, own=false))
                if h160_slice in state.targets.hashes
                    return (i + 2, copy(h160_slice))
                end
            end

            if lut[((Int(unsafe_load(p_h160 + 60, 1)) << 8) | Int(unsafe_load(p_h160 + 60, 2))) + 1]
                h160_slice = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160 + 60, 20, own=false))
                if h160_slice in state.targets.hashes
                    return (i + 3, copy(h160_slice))
                end
            end
        end
        i += 4
    end

    # 2. Resto do lote
    while i <= n
        @inbounds begin
            pt = points[i]
            
            # SHA256 Zero-GC
            if is_comp
                unsafe_store!(p_pad, iseven(pt.y.v1) ? 0x02 : 0x03, 1)
                FastField.write_32bytes!(state.padded_buf, 1, pt.x)
                BtcCrypto_M4.sha256_block_m4!(p_sha, p_pad)
            else
                unsafe_store!(p_pub, 0x04, 1)
                FastField.write_32bytes!(state.pub_buf, 1, pt.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt.y)
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha)
            end
            
            # RIPEMD-160 (Ultra Rápido Zero-GC)
            FastRipemd.ripemd160_32b!(p_sha, p_h160)
            
            if lut[((Int(unsafe_load(p_h160, 1)) << 8) | Int(unsafe_load(p_h160, 2))) + 1]
                h160_slice = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160, 20, own=false))
                if MultiTarget.check_hit(state.targets, h160_slice)
                    return (i, h160_slice)
                end
            end

            if state.both_formats
                unsafe_store!(p_pub, 0x04, 1)
                FastField.write_32bytes!(state.pub_buf, 1, pt.x)
                FastField.write_32bytes!(state.pub_buf, 33, pt.y)
                
                ccall((:CC_SHA256, "/usr/lib/system/libcommonCrypto.dylib"), Ptr{Cvoid}, 
                      (Ptr{UInt8}, UInt32, Ptr{UInt8}), p_pub, 65, p_sha)
                
                # RIPEMD-160 (Ultra Rápido Zero-GC)
                FastRipemd.ripemd160_32b!(p_sha, p_h160)
                
                if lut[((Int(unsafe_load(p_h160, 1)) << 8) | Int(unsafe_load(p_h160, 2))) + 1]
                    h160_slice_uncomp = Vector{UInt8}(unsafe_wrap(Vector{UInt8}, p_h160, 20, own=false))
                    if MultiTarget.check_hit(state.targets, h160_slice_uncomp)
                        return (i, h160_slice_uncomp)
                    end
                end
            end
        end
        i += 1
    end

    return (0, nothing)
end

end # module
