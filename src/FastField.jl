module FastField

# ═══════════════════════════════════════════════════════════════════
# FastField.jl — Aritmética de campo Fp (secp256k1) NATIVA PURA (v5)
#
# Performance Extrema: Implementação unrolled de 256 bits SEM BIGINT/GMP.
# Alvo: 4M+ chaves/segundo através de Redução Pseudo-Mersenne.
# ═══════════════════════════════════════════════════════════════════

export FE256, mul_mod, add_mod, sub_mod, sqr_mod, inv_mod, pow_mod, from_big, to_big, ONE, ZERO
export write_32bytes!

struct FE256
    v1::UInt64 # Low
    v2::UInt64
    v3::UInt64
    v4::UInt64 # High
end

const _P_V1 = 0xfffffffefffffc2f
const _P_V2 = 0xffffffffffffffff
const _P_V3 = 0xffffffffffffffff
const _P_V4 = 0xffffffffffffffff
const _P_BIG = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", base=16)

const ZERO = FE256(0, 0, 0, 0)
const ONE  = FE256(1, 0, 0, 0)

# K = 2^256 mod P = 2^32 + 977
const K_VAL = UInt64(0x1000003d1)

# p-2 for Fermat's Little Theorem inversion (secp256k1 prime)
# p = 2^256 - 2^32 - 977 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
# p-2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
const _P_MINUS_2_V1 = UInt64(0xfffffffefffffc2d)
const _P_MINUS_2_V2 = UInt64(0xffffffffffffffff)
const _P_MINUS_2_V3 = UInt64(0xffffffffffffffff)
const _P_MINUS_2_V4 = UInt64(0xffffffffffffffff)

# ── Conversões ────────────────────────────────────────────

function from_big(n::BigInt)::FE256
    n_mod = mod(n, _P_BIG)
    v1 = UInt64(n_mod & 0xffffffffffffffff)
    v2 = UInt64((n_mod >> 64) & 0xffffffffffffffff)
    v3 = UInt64((n_mod >> 128) & 0xffffffffffffffff)
    v4 = UInt64((n_mod >> 192) & 0xffffffffffffffff)
    return FE256(v1, v2, v3, v4)
end

function to_big(f::FE256)::BigInt
    return (BigInt(f.v4) << 192) | (BigInt(f.v3) << 128) | (BigInt(f.v2) << 64) | BigInt(f.v1)
end

FE256(n::Integer) = from_big(BigInt(n))

@inline function write_32bytes!(buf::AbstractVector{UInt8}, offset::Int, f::FE256)
    @inbounds begin
        p = pointer(buf, offset + 1)
        p64 = reinterpret(Ptr{UInt64}, p)
        # Bitcoin usa Big-Endian, então invertemos os bytes de cada UInt64
        # e escrevemos na ordem inversa das palavras (v4 -> v1)
        unsafe_store!(p64, bswap(f.v4), 1)
        unsafe_store!(p64, bswap(f.v3), 2)
        unsafe_store!(p64, bswap(f.v2), 3)
        unsafe_store!(p64, bswap(f.v1), 4)
    end
end

# ── Matemática Nativa Ultra-Rápida (Zero-GMP) ────────────────

@inline function add_carry_native(a::UInt64, b::UInt64, carry::UInt64)
    r, c1 = Base.add_with_overflow(a, b)
    r2, c2 = Base.add_with_overflow(r, carry)
    return r2, UInt64(c1) + UInt64(c2)
end

@inline function mac_with_carry(a::UInt64, b::UInt64, c::UInt64, carry::UInt64)
    p = Base.widemul(a, b)
    l = p % UInt64
    h = (p >> 64) % UInt64
    r1, c1 = Base.add_with_overflow(l, c)
    r2, c2 = Base.add_with_overflow(r1, carry)
    return r2, h + UInt64(c1) + UInt64(c2)
end

@inline function add_mod(a::FE256, b::FE256)::FE256
    # 1. Soma r = a + b
    r1, c = Base.add_with_overflow(a.v1, b.v1)
    r2, c = add_carry_native(a.v2, b.v2, UInt64(c))
    r3, c = add_carry_native(a.v3, b.v3, c)
    r4, c = add_carry_native(a.v4, b.v4, c)
    
    # 2. t = r + K (se r >= P, t terá carry out)
    t1, tc = Base.add_with_overflow(r1, K_VAL)
    t2, tc = add_carry_native(r2, UInt64(0), UInt64(tc))
    t3, tc = add_carry_native(r3, UInt64(0), tc)
    t4, tc = add_carry_native(r4, UInt64(0), tc)
    
    # Se houve carry na soma original (c=1) ou se r + K transbordou (tc=1),
    # então r >= P e devemos usar o valor reduzido t.
    mask = -UInt64(c | tc)
    
    return FE256(
        (t1 & mask) | (r1 & ~mask),
        (t2 & mask) | (r2 & ~mask),
        (t3 & mask) | (r3 & ~mask),
        (t4 & mask) | (r4 & ~mask)
    )
end

@inline function sub_mod(a::FE256, b::FE256)::FE256
    # 1. r = a - b
    r1, b1 = Base.sub_with_overflow(a.v1, b.v1)
    r2, b1 = sub_borrow(a.v2, b.v2, b1)
    r3, b1 = sub_borrow(a.v3, b.v3, b1)
    r4, b1 = sub_borrow(a.v4, b.v4, b1)
    
    # 2. s = r - K (se a < b, r é negativo e precisamos somar P, que é subtrair K no domínio wrap)
    s1, sb = Base.sub_with_overflow(r1, K_VAL)
    s2, sb = sub_borrow(r2, UInt64(0), sb)
    s3, sb = sub_borrow(r3, UInt64(0), sb)
    s4, sb = sub_borrow(r4, UInt64(0), sb)
    
    # Se houve borrow na subtração original (b1=true), usamos o valor reduzido s.
    mask = -UInt64(b1)
    
    return FE256(
        (s1 & mask) | (r1 & ~mask),
        (s2 & mask) | (r2 & ~mask),
        (s3 & mask) | (r3 & ~mask),
        (s4 & mask) | (r4 & ~mask)
    )
end

@inline function mul_mod(a::FE256, b::FE256)::FE256
    # Fase 1: Multiplicação 256x256 -> 512 bits (Colunar)
    @inline r1, c = mac_with_carry(a.v1, b.v1, UInt64(0), UInt64(0))
    r2, c = mac_with_carry(a.v1, b.v2, UInt64(0), c)
    r3, c = mac_with_carry(a.v1, b.v3, UInt64(0), c)
    r4, c = mac_with_carry(a.v1, b.v4, UInt64(0), c)
    r5 = c

    r2, c = mac_with_carry(a.v2, b.v1, r2, UInt64(0))
    r3, c = mac_with_carry(a.v2, b.v2, r3, c)
    r4, c = mac_with_carry(a.v2, b.v3, r4, c)
    r5, c = mac_with_carry(a.v2, b.v4, r5, c)
    r6 = c

    r3, c = mac_with_carry(a.v3, b.v1, r3, UInt64(0))
    r4, c = mac_with_carry(a.v3, b.v2, r4, c)
    r5, c = mac_with_carry(a.v3, b.v3, r5, c)
    r6, c = mac_with_carry(a.v3, b.v4, r6, c)
    r7 = c

    r4, c = mac_with_carry(a.v4, b.v1, r4, UInt64(0))
    r5, c = mac_with_carry(a.v4, b.v2, r5, c)
    r6, c = mac_with_carry(a.v4, b.v3, r6, c)
    r7, c = mac_with_carry(a.v4, b.v4, r7, c)
    r8 = c

    # Fase 2: Redução Pseudo-Mersenne Secp256k1 (K = 2^32 + 977)
    # p = 2^256 - K, logo x mod p = (x & (2^256-1)) + (x >> 256) * K
    # Repetir até resultado < 2^256, depois subtração condicional final
    K = 0x00000001000003d1
    
    # Primeira passagem: r1..r4 + (r5..r8) * K
    h1, c_red = mac_with_carry(r5, K, UInt64(0), UInt64(0))
    h2, c_red = mac_with_carry(r6, K, UInt64(0), c_red)
    h3, c_red = mac_with_carry(r7, K, UInt64(0), c_red)
    h4, c_red = mac_with_carry(r8, K, UInt64(0), c_red)
    h5 = c_red

    r1, cb = Base.add_with_overflow(r1, h1)
    r2, cb = add_carry_native(r2, h2, UInt64(cb))
    r3, cb = add_carry_native(r3, h3, cb)
    r4, cb = add_carry_native(r4, h4, cb)

    ov = h5 + UInt64(cb)
    rem_full = UInt128(ov) * K
    r1, cb1 = Base.add_with_overflow(r1, UInt64(rem_full & 0xffffffffffffffff))
    r2, cb2 = add_carry_native(r2, UInt64(rem_full >> 64), UInt64(cb1))
    r3, cb3 = add_carry_native(r3, UInt64(0), UInt64(cb2))
    r4, cb4 = add_carry_native(r4, UInt64(0), UInt64(cb3))

    # Fix the missing cb4: if cb4 == 1, we must add K_VAL since 2^256 = K_VAL mod P
    if cb4 > 0
        r1, cb1 = Base.add_with_overflow(r1, K_VAL)
        r2, cb2 = add_carry_native(r2, UInt64(0), UInt64(cb1))
        r3, cb3 = add_carry_native(r3, UInt64(0), UInt64(cb2))
        r4, cb4 = add_carry_native(r4, UInt64(0), UInt64(cb3))
    end

    # --- REDUÇÃO COMPLETA COM LOOP ---
    # Repetir redução enquanto resultado >= 2^256 (overflow em r4)
    # ou enquanto resultado >= p
    for _ in 1:3  # Máximo 3 iterações suficientes para 512->256 bits
        # Verificar se r4 overflowed (r >= 2^256) ou r >= p
        t1, tc = Base.add_with_overflow(r1, K_VAL)
        t2, tc = add_carry_native(r2, UInt64(0), UInt64(tc))
        t3, tc = add_carry_native(r3, UInt64(0), tc)
        t4, tc = add_carry_native(r4, UInt64(0), tc)
        
        mask = -UInt64(tc)
        
        # Se overflow (r >= p), usar r + K (equivale a r - p)
        r1 = (t1 & mask) | (r1 & ~mask)
        r2 = (t2 & mask) | (r2 & ~mask)
        r3 = (t3 & mask) | (r3 & ~mask)
        r4 = (t4 & mask) | (r4 & ~mask)
        
        # Se não houve overflow, pode parar
        tc == 0 && break
    end

    return FE256(r1, r2, r3, r4)
end

@inline function sqr_mod(a::FE256)::FE256
    # Versão otimizada de square poderia vir aqui, por enquanto usa mul
    return mul_mod(a, a)
end

@inline function pow_mod(a::FE256)::FE256
    # a^(p-2) mod p using Fermat's Little Theorem
    # p-2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
    res = ONE
    base = a
    
    # v1 = 0xfffffc2d (64 bits)
    for i in 0:63
        if ((_P_MINUS_2_V1 >> i) & 1) == 1
            res = mul_mod(res, base)
        end
        base = sqr_mod(base)
    end
    # v2 = 0xffffffffffffffff (64 bits)
    for i in 0:63
        if ((_P_MINUS_2_V2 >> i) & 1) == 1
            res = mul_mod(res, base)
        end
        base = sqr_mod(base)
    end
    # v3 = 0xffffffffffffffff (64 bits)
    for i in 0:63
        if ((_P_MINUS_2_V3 >> i) & 1) == 1
            res = mul_mod(res, base)
        end
        base = sqr_mod(base)
    end
    # v4 = 0xfffffffe (64 bits)
    for i in 0:63
        if ((_P_MINUS_2_V4 >> i) & 1) == 1
            res = mul_mod(res, base)
        end
        base = sqr_mod(base)
    end
    
    return res
end

@inline function inv_mod(a::FE256)::FE256
    a == ZERO && return ZERO
    return pow_mod(a)
end

@inline function isodd(a::FE256)::Bool
    return (a.v1 & 1) == 1
end

@inline function ge(a::FE256, b::FE256)::Bool
    if a.v4 != b.v4 return a.v4 > b.v4 end
    if a.v3 != b.v3 return a.v3 > b.v3 end
    if a.v2 != b.v2 return a.v2 > b.v2 end
    return a.v1 >= b.v1
end

@inline function lt(a::FE256, b::FE256)::Bool
    if a.v4 != b.v4 return a.v4 < b.v4 end
    if a.v3 != b.v3 return a.v3 < b.v3 end
    if a.v2 != b.v2 return a.v2 < b.v2 end
    return a.v1 < b.v1
end

# Base.isless for FE256
Base.isless(a::FE256, b::FE256) = lt(a, b)

# ── Helpers de Bits ────────────────────────────────────────

@inline function sub_borrow(a::UInt64, b::UInt64, borrow::Bool)
    r, b1 = Base.sub_with_overflow(a, b)
    if borrow
        r, b2 = Base.sub_with_overflow(r, UInt64(1))
        return r, b1 | b2
    end
    return r, b1
end

Base.:(==)(a::FE256, b::FE256) = (a.v1 == b.v1 && a.v2 == b.v2 && a.v3 == b.v3 && a.v4 == b.v4)
Base.isodd(a::FE256) = isodd(a.v1)
Base.iseven(a::FE256)  = iseven(a.v1)

end # module
