module FastSecp

# ═══════════════════════════════════════════════════════════════════
# FastSecp.jl — Ponto Jacobiano secp256k1 com FastField (FE256)
#
# PointJ: ponto na curva secp256k1 em coordenadas Jacobianas,
# com coordenadas tipadas como FE256 (campo Fp).
#
# Diferença do SecpOptimized: usa FE256 (tipado) ao invés de BigInt.
# Permite futura troca da implementação interna do campo sem alterar
# a lógica de curva (separação de responsabilidades).
# ═══════════════════════════════════════════════════════════════════

using ..FastField

export PointJ, PointA, point_add_jacobian, point_double_jacobian, G_J_fast, is_infinity

# Ponto Jacobiano com FE256
struct PointJ
    x::FE256
    y::FE256
    z::FE256
end

# Ponto Afim com FE256
struct PointA
    x::FE256
    y::FE256
end

# Ponto no infinito: z == 0
@inline is_infinity(p::PointJ)::Bool = (p.z == FastField.ZERO)

# Constantes secp256k1
const _Gx = FastField.from_big(parse(BigInt,
    "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", base=16))
const _Gy = FastField.from_big(parse(BigInt,
    "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", base=16))

const G_J_fast = PointJ(_Gx, _Gy, FastField.ONE)

# Constantes para aritmética de curva
const FE_2 = FastField.FE256(2)
const FE_3 = FastField.FE256(3)
const FE_4 = FastField.FE256(4)
const FE_8 = FastField.FE256(8)

"""
    point_double_jacobian(P)
Duplicação de ponto em coordenadas Jacobianas com FE256.
"""
function point_double_jacobian(P::PointJ)::PointJ
    is_infinity(P) && return P

    YY  = sqr_mod(P.y)
    S   = mul_mod(FE_4, mul_mod(P.x, YY))
    M   = mul_mod(FE_3, sqr_mod(P.x))   # b=0 no secp256k1
    X3  = sub_mod(sqr_mod(M), mul_mod(FE_2, S))
    Y3  = sub_mod(mul_mod(M, sub_mod(S, X3)), mul_mod(FE_8, sqr_mod(YY)))
    Z3  = mul_mod(FE_2, mul_mod(P.y, P.z))

    return PointJ(X3, Y3, Z3)
end

"""
    point_add_jacobian(P1, P2)
Adição de dois pontos em coordenadas Jacobianas com FE256.
Caminho mais rápido: usa G_step para soma incremental (sem inversão).
"""
function point_add_jacobian(P1::PointJ, P2::PointJ)::PointJ
    is_infinity(P1) && return P2
    is_infinity(P2) && return P1

    Z1Z1 = sqr_mod(P1.z)
    Z2Z2 = sqr_mod(P2.z)
    U1   = mul_mod(P1.x, Z2Z2)
    U2   = mul_mod(P2.x, Z1Z1)
    S1   = mul_mod(P1.y, mul_mod(P2.z, Z2Z2))
    S2   = mul_mod(P2.y, mul_mod(P1.z, Z1Z1))

    if U1 == U2
        S1 == S2 || return PointJ(FastField.ZERO, FastField.ZERO, FastField.ZERO)
        return point_double_jacobian(P1)
    end

    H  = sub_mod(U2, U1)
    I  = sqr_mod(mul_mod(FE_2, H))
    J  = mul_mod(H, I)
    r  = mul_mod(FE_2, sub_mod(S2, S1))
    V  = mul_mod(U1, I)

    X3 = sub_mod(sub_mod(sqr_mod(r), J), mul_mod(FE_2, V))
    Y3 = sub_mod(mul_mod(r, sub_mod(V, X3)), mul_mod(FE_2, mul_mod(S1, J)))

    # Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2) * H
    Z1pZ2 = add_mod(P1.z, P2.z)
    Z3 = mul_mod(sub_mod(sub_mod(sqr_mod(Z1pZ2), Z1Z1), Z2Z2), H)

    return PointJ(X3, Y3, Z3)
end

end # module FastSecp
