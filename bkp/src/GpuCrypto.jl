module GpuCrypto

using CUDA
export GpuUInt256, add_gpu, sub_gpu, mul_gpu, modP_gpu, PointGpuJacobian, add_gpu_jacobian, gpu_scan_batch, jacobian_to_affine_gpu, invP_gpu, pow_gpu

# Estrutura de 256 bits para GPU (4 x UInt64)
struct GpuUInt256
    v1::UInt64
    v2::UInt64
    v3::UInt64
    v4::UInt64
end
Base.zero(::Type{GpuUInt256}) = GpuUInt256(0,0,0,0)

struct PointGpuJacobian
    x::GpuUInt256
    y::GpuUInt256
    z::GpuUInt256
end

# Parâmetros secp256k1 (Hardcoded de forma segura para GPUs, evitam acesso à RAM do PC)
const P1_SEC = 0xFFFFFFFEFFFFFC2F
const P2_SEC = 0xFFFFFFFFFFFFFFFF
const P3_SEC = 0xFFFFFFFFFFFFFFFF
const P4_SEC = 0xFFFFFFFFFFFFFFFF

@inline function add_gpu(a::GpuUInt256, b::GpuUInt256)::GpuUInt256
    r1, c1 = Base.add_with_overflow(a.v1, b.v1)
    r2, c2 = Base.add_with_overflow(a.v2, b.v2)
    r2, c_v2 = Base.add_with_overflow(r2, UInt64(c1))
    r3, c3 = Base.add_with_overflow(a.v3, b.v3)
    r3, c_v3 = Base.add_with_overflow(r3, UInt64(c2 | c_v2))
    r4, c4 = Base.add_with_overflow(a.v4, b.v4)
    r4, c_out = Base.add_with_overflow(r4, UInt64(c3 | c_v3))
    
    if c4 || c_out || (r4 > P4_SEC) || (r4 == P4_SEC && r3 > P3_SEC) ||
       (r4 == P4_SEC && r3 == P3_SEC && r2 > P2_SEC) ||
       (r4 == P4_SEC && r3 == P3_SEC && r2 == P2_SEC && r1 >= P1_SEC)
        
        # Subtração "inline" de P para evitar loop infinito de recursão
        s1, b1 = Base.sub_with_overflow(r1, P1_SEC)
        s2, b2 = Base.sub_with_overflow(r2, P2_SEC)
        s2, b_v2 = Base.sub_with_overflow(s2, UInt64(b1))
        s3, b3 = Base.sub_with_overflow(r3, P3_SEC)
        s3, b_v3 = Base.sub_with_overflow(s3, UInt64(b2 | b_v2))
        s4, b4 = Base.sub_with_overflow(r4, P4_SEC)
        s4, b_out2 = Base.sub_with_overflow(s4, UInt64(b3 | b_v3))
        
        return GpuUInt256(s1, s2, s3, s4)
    end
    return GpuUInt256(r1, r2, r3, r4)
end

@inline function sub_gpu(a::GpuUInt256, b::GpuUInt256)::GpuUInt256
    r1, b1 = Base.sub_with_overflow(a.v1, b.v1)
    r2, b2 = Base.sub_with_overflow(a.v2, b.v2)
    r2, b_v2 = Base.sub_with_overflow(r2, UInt64(b1))
    r3, b3 = Base.sub_with_overflow(a.v3, b.v3)
    r3, b_v3 = Base.sub_with_overflow(r3, UInt64(b2 | b_v2))
    r4, b4 = Base.sub_with_overflow(a.v4, b.v4)
    r4, b_out = Base.sub_with_overflow(r4, UInt64(b3 | b_v3))

    if b4 || b_out
        # Adição "inline" de P para evitar loop infinito
        a1, c1 = Base.add_with_overflow(r1, P1_SEC)
        a2, c2 = Base.add_with_overflow(r2, P2_SEC)
        a2, c_v2 = Base.add_with_overflow(a2, UInt64(c1))
        a3, c3 = Base.add_with_overflow(r3, P3_SEC)
        a3, c_v3 = Base.add_with_overflow(a3, UInt64(c2 | c_v2))
        a4, c4 = Base.add_with_overflow(r4, P4_SEC)
        a4, c_out2 = Base.add_with_overflow(a4, UInt64(c3 | c_v3))
        
        return GpuUInt256(a1, a2, a3, a4)
    end
    return GpuUInt256(r1, r2, r3, r4)
end

@inline function modP_gpu(a::GpuUInt256)::GpuUInt256
    # Redução a mod P (secp256k1)
    if (a.v4 > P4_SEC) || (a.v4 == P4_SEC && a.v3 > P3_SEC) ||
       (a.v4 == P4_SEC && a.v3 == P3_SEC && a.v2 > P2_SEC) ||
       (a.v4 == P4_SEC && a.v3 == P3_SEC && a.v2 == P2_SEC && a.v1 >= P1_SEC)
        return sub_gpu(a, GpuUInt256(P1_SEC, P2_SEC, P3_SEC, P4_SEC))
    end
    return a
end

@inline function umul128(a::UInt64, b::UInt64)::Tuple{UInt64, UInt64}
    res = widen(a) * widen(b)
    return UInt64(res & 0xFFFFFFFFFFFFFFFF), UInt64(res >> 64)
end

@inline function mad128(a::UInt64, b::UInt64, c::UInt64, d::UInt64)::Tuple{UInt64, UInt64}
    res = widen(a) * widen(b) + widen(c) + widen(d)
    return UInt64(res & 0xFFFFFFFFFFFFFFFF), UInt64(res >> 64)
end

@inline function mul_gpu(A::GpuUInt256, B::GpuUInt256)::GpuUInt256
    # Multiplicador 256x256 -> 512 bits (Schoolbook unrolled otimizado)
    a1=A.v1; a2=A.v2; a3=A.v3; a4=A.v4
    b1=B.v1; b2=B.v2; b3=B.v3; b4=B.v4
    
    r1, c1 = umul128(a1, b1)
    r2, c2 = mad128(a2, b1, c1, UInt64(0))
    r3, c3 = mad128(a3, b1, c2, UInt64(0))
    r4, c4 = mad128(a4, b1, c3, UInt64(0))
    r5 = c4
    
    r2, c1 = mad128(a1, b2, r2, UInt64(0))
    r3, c2 = mad128(a2, b2, r3, c1)
    r4, c3 = mad128(a3, b2, r4, c2)
    r5, c4 = mad128(a4, b2, r5, c3)
    r6 = c4
    
    r3, c1 = mad128(a1, b3, r3, UInt64(0))
    r4, c2 = mad128(a2, b3, r4, c1)
    r5, c3 = mad128(a3, b3, r5, c2)
    r6, c4 = mad128(a4, b3, r6, c3)
    r7 = c4
    
    r4, c1 = mad128(a1, b4, r4, UInt64(0))
    r5, c2 = mad128(a2, b4, r5, c1)
    r6, c3 = mad128(a3, b4, r6, c2)
    r7, c4 = mad128(a4, b4, r7, c3)
    r8 = c4
    
    # Fast Reduction para secp256k1: P = 2^256 - K
    K_SEC = UInt64(0x00000001000003D1)
    
    s1, c1 = umul128(r5, K_SEC)
    s2, c2 = mad128(r6, K_SEC, c1, UInt64(0))
    s3, c3 = mad128(r7, K_SEC, c2, UInt64(0))
    s4, c4 = mad128(r8, K_SEC, c3, UInt64(0))
    s5 = c4
    
    res1, c1 = Base.add_with_overflow(r1, s1)
    res2, c2 = Base.add_with_overflow(r2, s2)
    res2, cv2 = Base.add_with_overflow(res2, UInt64(c1))
    res3, c3 = Base.add_with_overflow(r3, s3)
    res3, cv3 = Base.add_with_overflow(res3, UInt64(c2 | cv2))
    res4, c4 = Base.add_with_overflow(r4, s4)
    res4, cv4 = Base.add_with_overflow(res4, UInt64(c3 | cv3))
    
    s5 = s5 + UInt64(c4 | cv4)
    
    t1, t2 = umul128(s5, K_SEC)
    
    f1, c1 = Base.add_with_overflow(res1, t1)
    f2, c2 = Base.add_with_overflow(res2, t2)
    f2, cv2 = Base.add_with_overflow(f2, UInt64(c1))
    f3, c3 = Base.add_with_overflow(res3, UInt64(0))
    f3, cv3 = Base.add_with_overflow(f3, UInt64(c2 | cv2))
    f4, c4 = Base.add_with_overflow(res4, UInt64(0))
    f4, cv4 = Base.add_with_overflow(f4, UInt64(c3 | cv3))
    
    if c4 | cv4
        f1, cx = Base.add_with_overflow(f1, K_SEC)
        f2, cx2 = Base.add_with_overflow(f2, UInt64(cx))
        f3, cx3 = Base.add_with_overflow(f3, UInt64(cx2))
        f4, cx4 = Base.add_with_overflow(f4, UInt64(cx3))
    end
    
    return modP_gpu(GpuUInt256(f1, f2, f3, f4))
end

@inline function add_gpu_jacobian(P1::PointGpuJacobian, P2::PointGpuJacobian)::PointGpuJacobian
    # Fórmulas Reais de Adição Jacobianas (Versão Única e Estável)
    z1z1 = mul_gpu(P1.z, P1.z)
    z2z2 = mul_gpu(P2.z, P2.z)
    u1 = mul_gpu(P1.x, z2z2)
    u2 = mul_gpu(P2.x, z1z1)
    s1 = mul_gpu(P1.y, mul_gpu(P2.z, z2z2))
    s2 = mul_gpu(P2.y, mul_gpu(P1.z, z1z1))
    h = sub_gpu(u2, u1)
    r = sub_gpu(s2, s1)
    h2 = mul_gpu(h, h)
    h3 = mul_gpu(h, h2)
    v = mul_gpu(u1, h2)
    nx = sub_gpu(sub_gpu(mul_gpu(r, r), h3), add_gpu(v, v))
    ny = sub_gpu(mul_gpu(r, sub_gpu(v, nx)), mul_gpu(s1, h3))
    nz = mul_gpu(mul_gpu(P1.z, P2.z), h)
    return PointGpuJacobian(nx, ny, nz)
end
@inline function pow_gpu(a::GpuUInt256)::GpuUInt256
    res = GpuUInt256(1, 0, 0, 0)
    base = a
    
    # P-2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
    v1 = 0xFFFFFFFEFFFFFC2D
    v2 = 0xFFFFFFFFFFFFFFFF
    v3 = 0xFFFFFFFFFFFFFFFF
    v4 = 0xFFFFFFFFFFFFFFFF
    
    # v1
    for i in 0:63
        if ((v1 >> i) & 1) == 1
            res = mul_gpu(res, base)
        end
        base = mul_gpu(base, base)
    end
    # v2
    for i in 0:63
        if ((v2 >> i) & 1) == 1
            res = mul_gpu(res, base)
        end
        base = mul_gpu(base, base)
    end
    # v3
    for i in 0:63
        if ((v3 >> i) & 1) == 1
            res = mul_gpu(res, base)
        end
        base = mul_gpu(base, base)
    end
    # v4
    for i in 0:63
        if ((v4 >> i) & 1) == 1
            res = mul_gpu(res, base)
        end
        base = mul_gpu(base, base)
    end
    
    return res
end

@inline function invP_gpu(a::GpuUInt256)::GpuUInt256
    return pow_gpu(a)
end

@inline function jacobian_to_affine_gpu(p::PointGpuJacobian)::PointGpuJacobian
    # Afim: X = X * Z^-2, Y = Y * Z^-3
    invZ = invP_gpu(p.z)
    invZ2 = mul_gpu(invZ, invZ)
    invZ3 = mul_gpu(invZ2, invZ)
    return PointGpuJacobian(
        mul_gpu(p.x, invZ2),
        mul_gpu(p.y, invZ3),
        GpuUInt256(1, 0, 0, 0)
    )
end

end # module
