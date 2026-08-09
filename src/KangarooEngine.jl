module KangarooEngine

using ..FastField
using ..FastSecp

export KangarooState, init_kangaroo, run_kangaroo, find_key_with_kangaroo

mutable struct KangarooState
    jump_points::Vector{PointJ}
    jump_dists::Vector{BigInt}
    mid::BigInt
    tame_point::PointJ
    tame_dist::BigInt
    wild_point::PointJ
    wild_dist::BigInt
    tame_dp::Dict{FE256, BigInt}
    range_min::BigInt
    range_max::BigInt
    n_jumps::Int
    dp_mask::UInt64
end

function _precompute_jumps(range_size::BigInt)
    mean_jump = max(1, Int(ceil(sqrt(big(range_size)))) ÷ 2)
    n = max(4, floor(Int, log2(mean_jump)) + 1)
    jumps = Vector{PointJ}(undef, n)
    dists = Vector{BigInt}(undef, n)
    d = BigInt(1)
    @inbounds for i in 1:n
        jumps[i] = FastSecp.scalar_mul(d, FastSecp.G_J_fast)
        dists[i] = d
        d = min(d * 2, mean_jump)
    end
    return jumps, dists
end

function init_kangaroo(pub_hex::String, range_min::BigInt, range_max::BigInt)
    x, y = _decompress_pubkey(pub_hex)
    return init_kangaroo(string(x, base=16, pad=64), string(y, base=16, pad=64), range_min, range_max)
end

function _decompress_pubkey(pub_hex::String)
    raw = parse(BigInt, pub_hex, base=16)
    if length(pub_hex) == 130
        Qx = parse(BigInt, pub_hex[3:66], base=16)
        Qy = parse(BigInt, pub_hex[67:130], base=16)
        return Qx, Qy
    elseif length(pub_hex) == 66
        x = parse(BigInt, pub_hex[3:66], base=16)
        is_even = pub_hex[1:2] == "02"
        p = BigInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", base=16)
        y_sq = (x^3 + 7) % p
        q = (p + 1) ÷ 4
        y = powermod(y_sq, q, p)
        if iseven(y) != is_even
            y = p - y
        end
        return x, y
    else
        error("Formato de pubkey inválido: $pub_hex")
    end
end

function init_kangaroo(pubkey_x_hex::String, pubkey_y_hex::String,
                        range_min::BigInt, range_max::BigInt)
    Qx = FastField.from_big(parse(BigInt, pubkey_x_hex, base=16))
    Qy = FastField.from_big(parse(BigInt, pubkey_y_hex, base=16))
    Q = PointJ(Qx, Qy, FastField.ONE)
    range_size = range_max - range_min + 1
    jumps, dists = _precompute_jumps(range_size)
    mid = range_min + div(range_size, BigInt(2))
    tame_point = FastSecp.scalar_mul(mid, FastSecp.G_J_fast)
    expected_steps = Int(ceil(4 * sqrt(big(range_size))))
    expected_steps = min(expected_steps, typemax(Int32))
    dp_bits = max(1, floor(Int, log2(max(1, expected_steps ÷ 1000))))
    dp_mask = (UInt64(1) << dp_bits) - 1
    return KangarooState(jumps, dists, mid, tame_point, BigInt(0), Q, BigInt(0),
                         Dict{FE256, BigInt}(), range_min, range_max, length(jumps), dp_mask)
end

function _is_distinguished(state::KangarooState, p::PointJ)
    FastSecp.is_infinity(p) && return false
    aff = FastSecp.jacobian_to_affine(p)
    return (aff.x.v4 & state.dp_mask) == 0
end

function _batch_normalize_and_check(state::KangarooState, points::Vector{PointJ},
                                     dists::Vector{BigInt}, is_tame::Bool)
    len = length(points)
    len == 0 && return BigInt(-1)
    affs = FastSecp.batch_normalize(points)
    @inbounds for i in 1:len
        x = affs[i].x
        if (x.v4 & state.dp_mask) == 0
            if is_tame
                if !haskey(state.tame_dp, x)
                    state.tame_dp[x] = dists[i]
                end
            else
                if haskey(state.tame_dp, x)
                    return state.mid + state.tame_dp[x] - dists[i]
                end
            end
        end
    end
    return BigInt(-1)
end

function run_kangaroo(state::KangarooState; max_steps::Int=0)
    if max_steps <= 0
        range_size = state.range_max - state.range_min + 1
        max_steps = Int(ceil(4 * sqrt(big(range_size))))
        max_steps = min(max_steps, typemax(Int32))
    end
    batch_size = 256
    buf = Vector{PointJ}(undef, batch_size)
    dist_buf = Vector{BigInt}(undef, batch_size)

    total = 0
    while total < max_steps
        n = min(batch_size, max_steps - total)
        @inbounds for i in 1:n
            j = (state.tame_point.x.v1 % state.n_jumps) + 1
            state.tame_point = FastSecp.point_add_jacobian(state.tame_point, state.jump_points[j])
            state.tame_dist += state.jump_dists[j]
            buf[i] = state.tame_point
            dist_buf[i] = state.tame_dist
        end
        _batch_normalize_and_check(state, buf[1:n], dist_buf[1:n], true)
        total += n
    end

    wild_limit = max_steps * 4
    total = 0
    while total < wild_limit
        n = min(batch_size, wild_limit - total)
        @inbounds for i in 1:n
            j = (state.wild_point.x.v1 % state.n_jumps) + 1
            state.wild_point = FastSecp.point_add_jacobian(state.wild_point, state.jump_points[j])
            state.wild_dist += state.jump_dists[j]
            buf[i] = state.wild_point
            dist_buf[i] = state.wild_dist
        end
        result = _batch_normalize_and_check(state, buf[1:n], dist_buf[1:n], false)
        if result >= 0
            return result
        end
        total += n
    end
    return BigInt(-1)
end

function find_key_with_kangaroo(pubkey_x_hex::String, pubkey_y_hex::String,
                                 range_min::BigInt, range_max::BigInt)
    state = init_kangaroo(pubkey_x_hex, pubkey_y_hex, range_min, range_max)
    return run_kangaroo(state)
end

end
