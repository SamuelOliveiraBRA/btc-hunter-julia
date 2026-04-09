module FastField

# ═══════════════════════════════════════════════════════════════════
# FastField.jl — Aritmética de campo Fp (secp256k1) NATIVA PURA (v5)
#
# Performance Extrema: Implementação unrolled de 256 bits SEM BIGINT/GMP.
# Alvo: 4M+ chaves/segundo através de Redução Pseudo-Mersenne.
# ═══════════════════════════════════════════════════════════════════

export FE256, mul_mod, add_mod, sub_mod, sqr_mod, inv_mod, from_big, to_big, ONE, ZERO
export write_32bytes!

struct FE256
    v1::UInt64 # Low
    v2::UInt64
    v3::UInt64
    v4::UInt64 # High
end

const _P_V1 = 0xffffffffffffff2f
const _P_V2 = 0xffffffffffffffff
const _P_V3 = 0xffffffffffffffff
const _P_V4 = 0xffffffffffffffff
const _P_BIG = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", base=16)

const ZERO = FE256(0, 0, 0, 0)
const ONE  = FE256(1, 0, 0, 0)

# K = 2^256 mod P = 2^32 + 977
const K_VAL = UInt64(0x1000003d1)

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
        v = f.v4
        buf[offset+0] = (v >> 56) % UInt8; buf[offset+1] = (v >> 48) % UInt8
        buf[offset+2] = (v >> 40) % UInt8; buf[offset+3] = (v >> 32) % UInt8
        buf[offset+4] = (v >> 24) % UInt8; buf[offset+5] = (v >> 16) % UInt8
        buf[offset+6] = (v >> 8)  % UInt8; buf[offset+7] = (v)       % UInt8
        v = f.v3
        buf[offset+8] = (v >> 56) % UInt8; buf[offset+9] = (v >> 48) % UInt8
        buf[offset+10] = (v >> 40) % UInt8; buf[offset+11] = (v >> 32) % UInt8
        buf[offset+12] = (v >> 24) % UInt8; buf[offset+13] = (v >> 16) % UInt8
        buf[offset+14] = (v >> 8)  % UInt8; buf[offset+15] = (v)       % UInt8
        v = f.v2
        buf[offset+16] = (v >> 56) % UInt8; buf[offset+17] = (v >> 48) % UInt8
        buf[offset+18] = (v >> 40) % UInt8; buf[offset+19] = (v >> 32) % UInt8
        buf[offset+20] = (v >> 24) % UInt8; buf[offset+21] = (v >> 16) % UInt8
        buf[offset+22] = (v >> 8)  % UInt8; buf[offset+23] = (v)       % UInt8
        v = f.v1
        buf[offset+24] = (v >> 56) % UInt8; buf[offset+25] = (v >> 48) % UInt8
        buf[offset+26] = (v >> 40) % UInt8; buf[offset+27] = (v >> 32) % UInt8
        buf[offset+28] = (v >> 24) % UInt8; buf[offset+29] = (v >> 16) % UInt8
        buf[offset+30] = (v >> 8)  % UInt8; buf[offset+31] = (v)       % UInt8
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
    r1, c = Base.add_with_overflow(a.v1, b.v1)
    r2, c = add_carry_native(a.v2, b.v2, UInt64(c))
    r3, c = add_carry_native(a.v3, b.v3, c)
    r4, c = add_carry_native(a.v4, b.v4, c)
    
    if c != 0 || (r4 == _P_V4 && r3 == _P_V3 && r2 == _P_V2 && r1 >= _P_V1)
        r1, c = Base.add_with_overflow(r1, K_VAL)
        r2, c = add_carry_native(r2, 0x0000000000000000, UInt64(c))
        r3, c = add_carry_native(r3, 0x0000000000000000, c)
        r4, c = add_carry_native(r4, 0x0000000000000000, c)
    end
    return FE256(r1, r2, r3, r4)
end

@inline function sub_mod(a::FE256, b::FE256)::FE256
    r1, b1 = Base.sub_with_overflow(a.v1, b.v1)
    r2, b1 = sub_borrow(a.v2, b.v2, b1)
    r3, b1 = sub_borrow(a.v3, b.v3, b1)
    r4, b1 = sub_borrow(a.v4, b.v4, b1)
    
    if b1
        r1, b1 = Base.sub_with_overflow(r1, K_VAL)
        r2, b1 = sub_borrow(r2, 0x0000000000000000, b1)
        r3, b1 = sub_borrow(r3, 0x0000000000000000, b1)
        r4, b1 = sub_borrow(r4, 0x0000000000000000, b1)
    end
    return FE256(r1, r2, r3, r4)
end

@inline function mul_mod(a::FE256, b::FE256)::FE256
    # 256x256 -> 512 Multiplicação Escolar Unrolled
    r1, c = mac_with_carry(a.v1, b.v1, 0x0000000000000000, 0x0000000000000000)
    r2, c = mac_with_carry(a.v1, b.v2, 0x0000000000000000, c)
    r3, c = mac_with_carry(a.v1, b.v3, 0x0000000000000000, c)
    r4, c = mac_with_carry(a.v1, b.v4, 0x0000000000000000, c)
    r5 = c

    r2, c = mac_with_carry(a.v2, b.v1, r2, 0x0000000000000000)
    r3, c = mac_with_carry(a.v2, b.v2, r3, c)
    r4, c = mac_with_carry(a.v2, b.v3, r4, c)
    r5, c = mac_with_carry(a.v2, b.v4, r5, c)
    r6 = c

    r3, c = mac_with_carry(a.v3, b.v1, r3, 0x0000000000000000)
    r4, c = mac_with_carry(a.v3, b.v2, r4, c)
    r5, c = mac_with_carry(a.v3, b.v3, r5, c)
    r6, c = mac_with_carry(a.v3, b.v4, r6, c)
    r7 = c

    r4, c = mac_with_carry(a.v4, b.v1, r4, 0x0000000000000000)
    r5, c = mac_with_carry(a.v4, b.v2, r5, c)
    r6, c = mac_with_carry(a.v4, b.v3, r6, c)
    r7, c = mac_with_carry(a.v4, b.v4, r7, c)
    r8 = c

    # Redução Pseudo-Mersenne Secp256k1 (P = 2^256 - 2^32 - 977)
    # Target: L + H * K_VAL onde K_VAL = 2^32 + 977
    K = 0x00000001000003d1
    
    h1, c = mac_with_carry(r5, K, 0x0000000000000000, 0x0000000000000000)
    h2, c = mac_with_carry(r6, K, 0x0000000000000000, c)
    h3, c = mac_with_carry(r7, K, 0x0000000000000000, c)
    h4, c = mac_with_carry(r8, K, 0x0000000000000000, c)
    h5 = c

    r1, cb = Base.add_with_overflow(r1, h1)
    r2, cb = add_carry_native(r2, h2, UInt64(cb))
    r3, cb = add_carry_native(r3, h3, cb)
    r4, cb = add_carry_native(r4, h4, cb)
    c2     = cb + h5 

    h1, c = mac_with_carry(c2, K, 0x0000000000000000, 0x0000000000000000)
    h2 = c

    r1, cb = Base.add_with_overflow(r1, h1)
    r2, cb = add_carry_native(r2, h2, UInt64(cb))
    r3, cb = add_carry_native(r3, 0x0000000000000000, cb)
    r4, cb = add_carry_native(r4, 0x0000000000000000, cb)

    if cb != 0 || (r4 == _P_V4 && r3 == _P_V3 && r2 == _P_V2 && r1 >= _P_V1)
        r1, cb = Base.add_with_overflow(r1, K)
        r2, cb = add_carry_native(r2, 0x0000000000000000, UInt64(cb))
        r3, cb = add_carry_native(r3, 0x0000000000000000, cb)
        r4, cb = add_carry_native(r4, 0x0000000000000000, cb)
    end

    return FE256(r1, r2, r3, r4)
end

@inline function sqr_mod(a::FE256)::FE256
    return mul_mod(a, a)
end

@inline function inv_mod(a::FE256)::FE256
    a == ZERO && return ZERO
    return from_big(invmod(to_big(a), _P_BIG))
end

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
