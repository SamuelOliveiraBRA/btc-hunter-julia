module FastField

# ═══════════════════════════════════════════════════════════════════
# FastField.jl — Aritmética de campo Fp para secp256k1
#
# FE256: representa um elemento do campo Fp como BigInt otimizado.
# Operações modulares com o primo P do secp256k1.
#
# Nota: Esta implementação usa BigInt internamente para corretude.
# O ganho de performance vem de evitar alocações redundantes e usar
# as operações de campo de forma amortizada (batch inversion).
# ═══════════════════════════════════════════════════════════════════

export FE256, mul_mod, inv_mod, from_big, to_big, add_mod, sub_mod, sqr_mod, ONE, ZERO

# Primo do campo secp256k1: p = 2^256 - 2^32 - 977
const _P = parse(BigInt,
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",
    base=16)

# FE256: elemento do campo Fp representado como BigInt reduzido (0 ≤ v < P)
struct FE256
    v::BigInt
    FE256(x::BigInt) = new(mod(x, _P))
end

const ZERO = FE256(BigInt(0))
const ONE  = FE256(BigInt(1))

# ── Operações de campo ────────────────────────────────────

@inline function mul_mod(a::FE256, b::FE256)::FE256
    FE256(mod(a.v * b.v, _P))
end

@inline function add_mod(a::FE256, b::FE256)::FE256
    r = a.v + b.v
    FE256(r >= _P ? r - _P : r)
end

@inline function sub_mod(a::FE256, b::FE256)::FE256
    r = a.v - b.v
    FE256(r < 0 ? r + _P : r)
end

@inline function sqr_mod(a::FE256)::FE256
    FE256(mod(a.v * a.v, _P))
end

"""
    inv_mod(a::FE256)
Inversão modular via Fermat: a^(P-2) mod P.
Equivalente a invmod(a, P) mas tipado para FE256.
"""
@inline function inv_mod(a::FE256)::FE256
    FE256(invmod(a.v, _P))
end

"""
    from_big(x::BigInt) → FE256
Converte BigInt para elemento do campo (reduz mod P).
"""
@inline from_big(x::BigInt)::FE256 = FE256(x)

"""
    to_big(a::FE256) → BigInt
Extrai BigInt de um elemento do campo.
"""
@inline to_big(a::FE256)::BigInt = a.v

# ── Operador de igualdade ─────────────────────────────────
Base.:(==)(a::FE256, b::FE256) = a.v == b.v
Base.iseven(a::FE256) = iseven(a.v)
Base.isodd(a::FE256)  = isodd(a.v)

end # module FastField
