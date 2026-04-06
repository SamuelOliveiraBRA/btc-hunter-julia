module Base58

export encode, decode

const base58Alphabet = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y',
    'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'o', 'p',
    'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
]

# Tabela de decodificação: ASCII → índice Base58 (255 = inválido)
const b58 = let tbl = fill(UInt8(255), 256)
    for (i, c) in enumerate(base58Alphabet)
        tbl[UInt8(c) + 1] = i - 1
    end
    tbl
end

# ─────────────────────────────────────────
# Encode
# ─────────────────────────────────────────

"""
    encode(input::Vector{UInt8}) -> String
Codifica bytes em Base58 (sem checksum).
"""
function encode(input::Vector{UInt8})::String
    # Converte Vector{UInt8} → BigInt (big-endian)
    x = BigInt(0)
    for b in input
        x = x * 256 + b
    end

    base = BigInt(58)
    result = Char[]

    while x > 0
        x, mod = divrem(x, base)
        pushfirst!(result, base58Alphabet[Int(mod) + 1])
    end

    # Zeros à esquerda viram '1'
    for b in input
        b != 0x00 && break
        pushfirst!(result, base58Alphabet[1])
    end

    return String(result)
end

# ─────────────────────────────────────────
# Decode
# ─────────────────────────────────────────

"""
    decode(s::String) -> Vector{UInt8}
Decodifica uma string Base58 para bytes.
"""
function decode(s::String)::Vector{UInt8}
    answer = BigInt(0)
    base   = BigInt(58)

    for c in s
        v = UInt32(c)
        if v > 255 || b58[v + 1] == 0xff
            error("Caractere inválido no Base58: '$c'")
        end
        answer = answer * base + b58[v + 1]
    end

    # Converte BigInt → bytes (big-endian)
    bytes = UInt8[]
    while answer > 0
        pushfirst!(bytes, UInt8(answer % 256))
        answer ÷= 256
    end

    # Zeros à esquerda ('1' no Base58 → 0x00)
    leading_zeros = count(c -> c == '1', Iterators.takewhile(c -> c == '1', s))
    return vcat(zeros(UInt8, leading_zeros), bytes)
end

end # module Base58
