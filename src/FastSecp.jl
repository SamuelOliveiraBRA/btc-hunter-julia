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

"""
    scalar_mul(k::BigInt, P::PointJ)::PointJ
Multiplicação escalar básica (Double-and-Add) para coordenadas Jacobianas.
"""
function scalar_mul(k::BigInt, P::PointJ)::PointJ
    res = PointJ(FastField.ZERO, FastField.ZERO, FastField.ZERO) # Ponto no infinito
    addend = P
    
    bin_k = string(k, base=2)
    for i in 1:length(bin_k)
        res = point_double_jacobian(res)
        if bin_k[i] == '1'
            res = point_add_jacobian(res, addend)
        end
    end
    return res
end

"""
    negate_point(p::PointJ)::PointJ
"""
function negate_point(p::PointJ)::PointJ
    return PointJ(p.x, sub_mod(FastField.ZERO, p.y), p.z)
end

"""
    batch_normalize(points::Vector{PointJ})::Vector{PointA}
Aplica Montgomery Batch Inversion para transformar múltiplos pontos Jacobianos em Afins (X, Y)
usando apenas UMA inversão modular.
"""
function batch_normalize(points::Vector{PointJ})::Vector{PointA}
    len = length(points)
    len == 0 && return PointA[]
    
    # Extrair Z coords
    zs = [p.z for p in points]
    
    # Algoritmo de Montgomery
    partials = Vector{FE256}(undef, len)
    partials[1] = zs[1]
    for i in 2:len
        partials[i] = mul_mod(partials[i-1], zs[i])
    end
    
    # Uma única inversão modular pesada
    inv_all = inv_mod(partials[len])
    
    results = Vector{PointA}(undef, len)
    
    for i in len:-1:2
        inv_z = mul_mod(inv_all, partials[i-1])
        inv_all = mul_mod(inv_all, zs[i])
        
        iz2 = sqr_mod(inv_z)
        iz3 = mul_mod(iz2, inv_z)
        
        results[i] = PointA(mul_mod(points[i].x, iz2), mul_mod(points[i].y, iz3))
    end
    
    # O primeiro elemento
    iz2 = sqr_mod(inv_all)
    iz3 = mul_mod(iz2, inv_all)
    results[1] = PointA(mul_mod(points[1].x, iz2), mul_mod(points[1].y, iz3))
    
    return results
end

"""
    jacobian_to_affine(p::PointJ)::PointA
"""
function jacobian_to_affine(p::PointJ)::PointA
    is_infinity(p) && return PointA(FastField.ZERO, FastField.ZERO)
    inv_z = inv_mod(p.z)
    iz2 = sqr_mod(inv_z)
    iz3 = mul_mod(iz2, inv_z)
    return PointA(mul_mod(p.x, iz2), mul_mod(p.y, iz3))
end

end # module FastSecp
