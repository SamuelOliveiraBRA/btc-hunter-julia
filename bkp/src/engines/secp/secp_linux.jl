module SecpEngine

export PointJacobian, add_points_jacobian, double_point_jacobian, negate_point_jacobian, scalar_mul, batch_normalize, jacobian_to_affine, P, n, G_J

# Parâmetros secp256k1
const P = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", base=16)
const n = parse(BigInt, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", base=16)
const Gx = parse(BigInt, "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", base=16)
const Gy = parse(BigInt, "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", base=16)

struct PointJacobian
    X::BigInt
    Y::BigInt
    Z::BigInt
end

const G_J = PointJacobian(Gx, Gy, 1)

"""
    scalar_mul(k::BigInt, P::PointJacobian)
Multiplicação escalar básica (Double-and-Add) para coordenadas Jacobianas.
Usada apenas para definir o ponto inicial dos workers.
"""
function scalar_mul(k::BigInt, P::PointJacobian)::PointJacobian
    res = PointJacobian(0, 0, 0) # Infinito
    addend = P
    
    bin_k = string(k, base=2)
    
    for i in 1:length(bin_k)
        # Double
        res = double_point_jacobian(res)
        if bin_k[i] == '1'
            # Add
            res = add_points_jacobian(res, addend)
        end
    end
    return res
end

"""
    double_point_jacobian(P1)
Duplicação de ponto em coordenadas Jacobianas.
"""
function double_point_jacobian(P1::PointJacobian)::PointJacobian
    P1.Z == 0 && return P1
    
    # Fórmulas de duplicação para Jacobianas
    YY = sqr_mod(P1.Y)
    S = mul_mod(4, mul_mod(P1.X, YY))
    M = add_mod(mul_mod(3, sqr_mod(P1.X)), 0) # b=0 no secp256k1
    X3 = sub_mod(sqr_mod(M), mul_mod(2, S))
    Y3 = sub_mod(mul_mod(M, sub_mod(S, X3)), mul_mod(8, sqr_mod(YY)))
    Z3 = mul_mod(2, mul_mod(P1.Y, P1.Z))
    
    return PointJacobian(X3, Y3, Z3)
end

# Aritmética Modular básica
@inline modP(x) = mod(x, P)
@inline add_mod(a, b) = modP(a + b)
@inline sub_mod(a, b) = modP(a - b)
@inline mul_mod(a, b) = modP(a * b)
@inline sqr_mod(a)   = modP(a * a)

"""
    add_points_jacobian(P1, P2)
Soma de dois pontos em coordenadas Jacobianas.
Evita inversão modular completamente durante a conta interna.
"""
function add_points_jacobian(P1::PointJacobian, P2::PointJacobian)::PointJacobian
    # Se um for o ponto no infinito (Z=0)
    P1.Z == 0 && return P2
    P2.Z == 0 && return P1

    # Fórmulas de adição para coordenadas Jacobianas
    Z1Z1 = sqr_mod(P1.Z)
    Z2Z2 = sqr_mod(P2.Z)
    
    U1 = mul_mod(P1.X, Z2Z2)
    U2 = mul_mod(P2.X, Z1Z1)
    
    S1 = mul_mod(P1.Y, mul_mod(P2.Z, Z2Z2))
    S2 = mul_mod(P2.Y, mul_mod(P1.Z, Z1Z1))
    
    if U1 == U2
        if S1 != S2
            return PointJacobian(0, 0, 0) # Ponto no infinito
        else
            # Duplicação de ponto (não comumente usada no sequential scan, mas necessária)
            YY = sqr_mod(P1.Y)
            S = mul_mod(4, mul_mod(P1.X, YY))
            M = add_mod(mul_mod(3, sqr_mod(P1.X)), 0) # b=0 no secp256k1
            X3 = sub_mod(sqr_mod(M), mul_mod(2, S))
            Y3 = sub_mod(mul_mod(M, sub_mod(S, X3)), mul_mod(8, sqr_mod(YY)))
            Z3 = mul_mod(2, mul_mod(P1.Y, P1.Z))
            return PointJacobian(X3, Y3, Z3)
        end
    end
    
    H = sub_mod(U2, U1)
    I = sqr_mod(mul_mod(2, H))
    J = mul_mod(H, I)
    r = mul_mod(2, sub_mod(S2, S1))
    V = mul_mod(U1, I)
    
    X3 = sub_mod(sub_mod(sqr_mod(r), J), mul_mod(2, V))
    Y3 = sub_mod(mul_mod(r, sub_mod(V, X3)), mul_mod(2, mul_mod(S1, J)))
    Z3 = mul_mod(modP(add_mod(P1.Z, P2.Z)^2 - Z1Z1 - Z2Z2), H)
    
    return PointJacobian(X3, Y3, Z3)
end

"""
    negate_point_jacobian(P::PointJacobian)
Retorna -P em coordenadas Jacobianas.
"""
function negate_point_jacobian(P1::PointJacobian)::PointJacobian
    return PointJacobian(P1.X, sub_mod(0, P1.Y), P1.Z)
end

"""
    batch_normalize(points::Vector{PointJacobian})
Aplica Montgomery Batch Inversion para transformar múltiplos pontos Jacobianos em Afins (X, Y)
de uma só vez usando apenas UMA inversão modular pesada.
"""
function batch_normalize(points::Vector{PointJacobian})
    len = length(points)
    len == 0 && return []
    
    # Extrair Z coords
    zs = [p.Z for p in points]
    
    # Algoritmo de Montgomery
    partials = Vector{BigInt}(undef, len)
    partials[1] = zs[1]
    for i in 2:len
        partials[i] = mul_mod(partials[i-1], zs[i])
    end
    
    # Uma única inversão modular pesada
    inv_all = invmod(partials[len], P)
    
    results = Vector{Tuple{BigInt, BigInt}}(undef, len)
    
    for i in len:-1:2
        inv_z = mul_mod(inv_all, partials[i-1])
        inv_all = mul_mod(inv_all, zs[i])
        
        iz2 = sqr_mod(inv_z)
        iz3 = mul_mod(iz2, inv_z)
        
        results[i] = (mul_mod(points[i].X, iz2), mul_mod(points[i].Y, iz3))
    end
    
    # O primeiro elemento
    iz2 = sqr_mod(inv_all)
    iz3 = mul_mod(iz2, inv_all)
    results[1] = (mul_mod(points[1].X, iz2), mul_mod(points[1].Y, iz3))
    
    return results
end

"""
    jacobian_to_affine(p::PointJacobian)
Versão unitária para validação.
"""
function jacobian_to_affine(p::PointJacobian)
    p.Z == 0 && return (BigInt(0), BigInt(0))
    inv_z = invmod(p.Z, P)
    iz2 = sqr_mod(inv_z)
    iz3 = mul_mod(iz2, inv_z)
    return (mul_mod(p.X, iz2), mul_mod(p.Y, iz3))
end

end # module
