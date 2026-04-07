module FastField

export FE256, add_mod!, sub_mod!, mul_mod!, inv_mod, to_big, from_big

# ── Estrutura UInt256 (4x UInt64) ────────────────────────
struct FE256
    w0::UInt64
    w1::UInt64
    w2::UInt64
    w3::UInt64
end

# Primo P do Secp256k1: 2^256 - 2^32 - 977
# P = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F
const P0 = 0xfffffffefffffc2f
const P1 = 0xffffffffffffffff
const P2 = 0xffffffffffffffff
const P3 = 0xffffffffffffffff

# Zero e Um
const ZERO = FE256(0,0,0,0)
const ONE  = FE256(1,0,0,0)

# Converter de/para BigInt (para validação e inicialização)
function from_big(n::BigInt)
    w0 = UInt64(n & 0xffffffffffffffff)
    w1 = UInt64((n >> 64) & 0xffffffffffffffff)
    w2 = UInt64((n >> 128) & 0xffffffffffffffff)
    w3 = UInt64((n >> 192) & 0xffffffffffffffff)
    return FE256(w0, w1, w2, w3)
end

function to_big(f::FE256)
    return BigInt(f.w0) | (BigInt(f.w1) << 64) | (BigInt(f.w2) << 128) | (BigInt(f.w3) << 192)
end

# ── Soma Modular ──────────────────────────────────────────
@noinline function _add_slow(a, b)
    ba = to_big(a); bb = to_big(b)
    bp = to_big(FE256(P0, P1, P2, P3))
    return from_big((ba + bb) % bp)
end

@inline function add_mod(a::FE256, b::FE256)
    low  = UInt128(a.w0) + b.w0
    mid1 = UInt128(a.w1) + b.w1 + (low >> 64)
    mid2 = UInt128(a.w2) + b.w2 + (mid1 >> 64)
    high = UInt128(a.w3) + b.w3 + (mid2 >> 64)
    
    res0 = UInt64(low & 0xffffffffffffffff)
    res1 = UInt64(mid1 & 0xffffffffffffffff)
    res2 = UInt64(mid2 & 0xffffffffffffffff)
    res3 = UInt64(high & 0xffffffffffffffff)
    carry = UInt64(high >> 64)
    
    # Se houve carry ou se res >= P, subtrai P
    if carry > 0 || res3 > P3 || (res3 == P3 && (res2 > P2 || (res2 == P2 && (res1 > P1 || (res1 == P1 && res0 >= P0)))))
        l  = Int128(res0) - P0
        m1 = Int128(res1) - P1 + (l >> 64)
        m2 = Int128(res2) - P2 + (m1 >> 64)
        h  = Int128(res3) - P3 + (m2 >> 64)
        # Nota: O carry do 256-bit sum (carry=1) é anulado pela subtração de P (que é ~2^256)
        return FE256(UInt64(l & 0xffffffffffffffff), UInt64(m1 & 0xffffffffffffffff), UInt64(m2 & 0xffffffffffffffff), UInt64(h & 0xffffffffffffffff))
    end
    
    return FE256(res0, res1, res2, res3)
end

# ── Subtração Modular ───────────────────────────────────────
@inline function sub_mod(a::FE256, b::FE256)
    low  = Int128(a.w0) - b.w0
    mid1 = Int128(a.w1) - b.w1 + (low >> 64)
    mid2 = Int128(a.w2) - b.w2 + (mid1 >> 64)
    high = Int128(a.w3) - b.w3 + (mid2 >> 64)
    
    res0 = UInt64(low & 0xffffffffffffffff)
    res1 = UInt64(mid1 & 0xffffffffffffffff)
    res2 = UInt64(mid2 & 0xffffffffffffffff)
    res3 = UInt64(high & 0xffffffffffffffff)
    
    # Se negativo, soma P
    if (high >> 64) != 0
        l  = UInt128(res0) + P0
        m1 = UInt128(res1) + P1 + (l >> 64)
        m2 = UInt128(res2) + P2 + (m1 >> 64)
        h  = UInt128(res3) + P3 + (m2 >> 64)
        return FE256(UInt64(l & 0xffffffffffffffff), UInt64(m1 & 0xffffffffffffffff), UInt64(m2 & 0xffffffffffffffff), UInt64(h & 0xffffffffffffffff))
    end
    
    return FE256(res0, res1, res2, res3)
end

# ── Multiplicação Nativa (Secp256k1 Field) ───────────────────
# Implementação de multiplicação 256x256 -> 512 bits com redução rápida para P
function mul_mod(a::FE256, b::FE256)
    # 1. Multiplicação Escolar (Base 2^64) -> r[0:7]
    # Usamos UInt128 para os produtos parciais e carries
    r0::UInt128 = UInt128(a.w0) * b.w0
    r1::UInt128 = UInt128(a.w0) * b.w1 + UInt128(a.w1) * b.w0 + (r0 >> 64)
    r2::UInt128 = UInt128(a.w0) * b.w2 + UInt128(a.w1) * b.w1 + UInt128(a.w2) * b.w0 + (r1 >> 64)
    r3::UInt128 = UInt128(a.w0) * b.w3 + UInt128(a.w1) * b.w2 + UInt128(a.w2) * b.w1 + UInt128(a.w3) * b.w0 + (r2 >> 64)
    # ... e assim por diante para os 512 bits
    
    # NOTA: Para performance máxima e corretude sem falhas de carry em cascata, 
    # o ideal em Julia é usar a biblioteca nativa ou uma implementação via LLVM IR.
    # Como queremos AVX2, vamos por enquanto usar a versão BigInt para segurança até o 
    # Dashboard estar funcional, e depois faremos o "AutoTuning" para trocar a engine.
    
    # No entanto, vamos otimizar a conversão para BigInt para reduzir o overhead.
    ba = to_big(a)
    bb = to_big(b)
    bp = to_big(FE256(P0, P1, P2, P3))
    res = (ba * bb) % bp
    return from_big(res)
end

# Inversão Modular (Fermat's Little Theorem: a^(P-2) mod P)
function inv_mod(a::FE256)
    ba = to_big(a)
    bp = to_big(FE256(P0, P1, P2, P3))
    res = powermod(ba, bp - 2, bp)
    return from_big(res)
end

end # module
