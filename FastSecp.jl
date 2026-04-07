module FastSecp

using ..FastField

export PointJ, point_add_jacobian, point_double_jacobian, to_affine

# ── Estrutura de Ponto Jacobiano (x, y, z) ────────────────
struct PointJ
    x::FE256
    y::FE256
    z::FE256
end

# ── Soma de Pontos Jacobianos (P + Q) ──────────────────────
# Referência: Hyperelliptic Curve group law
# Usando fórmulas otimizadas para diminuir multiplicações
function point_add_jacobian(P::PointJ, Q::PointJ)
    # Z1^2, Z2^2
    z1z1 = FastField.mul_mod(P.z, P.z)
    z2z2 = FastField.mul_mod(Q.z, Q.z)
    
    # U1 = X1*Z2^2, U2 = X2*Z1^2
    u1 = FastField.mul_mod(P.x, z2z2)
    u2 = FastField.mul_mod(Q.x, z1z1)
    
    # S1 = Y1*Z2^3, S2 = Y2*Z1^3
    s1 = FastField.mul_mod(P.y, FastField.mul_mod(Q.z, z2z2))
    s2 = FastField.mul_mod(Q.y, FastField.mul_mod(P.z, z1z1))
    
    if u1 == u2
        if s1 == s2
            return point_double_jacobian(P)
        else
            return PointJ(FastField.ZERO, FastField.ZERO, FastField.ZERO)
        end
    end
    
    # H = U2 - U1, R = S2 - S1
    h = FastField.sub_mod(u2, u1)
    r = FastField.sub_mod(s2, s1)
    
    # H^2, H^3, U1*H^2
    hh = FastField.mul_mod(h, h)
    hhh = FastField.mul_mod(h, hh)
    v = FastField.mul_mod(u1, hh)
    
    # X3 = R^2 - H^3 - 2*V
    x3 = FastField.sub_mod(FastField.sub_mod(FastField.mul_mod(r, r), hhh), FastField.add_mod(v, v))
    
    # Y3 = R*(V - X3) - S1*H^3
    y3 = FastField.sub_mod(FastField.mul_mod(r, FastField.sub_mod(v, x3)), FastField.mul_mod(s1, hhh))
    
    # Z3 = Z1*Z2*H
    z3 = FastField.mul_mod(FastField.mul_mod(P.z, Q.z), h)
    
    return PointJ(x3, y3, z3)
end

# ── Dobro de Ponto Jacobiano (2*P) ────────────────────────
function point_double_jacobian(P::PointJ)
    if P.y == FastField.ZERO
        return PointJ(FastField.ZERO, FastField.ZERO, FastField.ZERO)
    end
    
    # a = 0 para Secp256k1, simplifica as fórmulas:
    # XX = X1^2, YY = Y1^2, YYYY = YY^2, ZZ = Z1^2
    xx = FastField.mul_mod(P.x, P.x)
    yy = FastField.mul_mod(P.y, P.y)
    yyyy = FastField.mul_mod(yy, yy)
    
    # S = 2*((X1+YY)^2 - XX - YYYY) = 4*X1*YY
    s = FastField.add_mod(FastField.mul_mod(P.x, yy), FastField.mul_mod(P.x, yy))
    s = FastField.add_mod(s, s)
    
    # M = 3*XX + a*ZZ^2 = 3*XX
    m = FastField.add_mod(FastField.add_mod(xx, xx), xx)
    
    # T = M^2 - 2*S
    t = FastField.sub_mod(FastField.mul_mod(m, m), FastField.add_mod(s, s))
    
    # X3 = T
    x3 = t
    # Y3 = M*(S - T) - 8*YYYY
    y8 = FastField.add_mod(yyyy, yyyy) # 2
    y8 = FastField.add_mod(y8, y8)     # 4
    y8 = FastField.add_mod(y8, y8)     # 8
    y3 = FastField.sub_mod(FastField.mul_mod(m, FastField.sub_mod(s, t)), y8)
    
    # Z3 = 2*Y1*Z1
    z3 = FastField.add_mod(FastField.mul_mod(P.y, P.z), FastField.mul_mod(P.y, P.z))
    
    return PointJ(x3, y3, z3)
end

# Converter para Afim (x, y)
function to_affine(P::PointJ)
    if P.z == FastField.ZERO
        return (FastField.ZERO, FastField.ZERO)
    end
    iz = FastField.inv_mod(P.z)
    iz2 = FastField.mul_mod(iz, iz)
    iz3 = FastField.mul_mod(iz, iz2)
    return (FastField.mul_mod(P.x, iz2), FastField.mul_mod(P.y, iz3))
end

end # module
