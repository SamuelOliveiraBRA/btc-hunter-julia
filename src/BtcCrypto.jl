module BtcCrypto

using SHA
using Secp256k1
include("SecpOptimized.jl")
using .SecpOptimized

export hash160, sha256, ripemd160, priv_to_pub_compressed, hex_to_bytes, bytes_to_hex, base58_to_hash160, serialize_compressed_batch, serialize_uncompressed_batch

"""
    sha256(data::Vector{UInt8})
Usa libcrypto (OpenSSL) para máxima performance.
"""
function sha256(data::Vector{UInt8})::Vector{UInt8}
    out = zeros(UInt8, 32)
    ccall((:SHA256, "libcrypto"), Ptr{UInt8}, (Ptr{UInt8}, Csize_t, Ptr{UInt8}), data, length(data), out)
    return out
end

"""
    ripemd160(data::Vector{UInt8})
Implementação via libcrypto (OpenSSL/LibreSSL) presente no macOS e Linux.
Muito mais rápido que implementações puras.
"""
function ripemd160(data::Vector{UInt8})::Vector{UInt8}
    out = zeros(UInt8, 20)
    # No macOS, libcrypto está disponível globalmente
    ccall((:RIPEMD160, "libcrypto"), Ptr{UInt8}, (Ptr{UInt8}, Csize_t, Ptr{UInt8}), data, length(data), out)
    return out
end

"""
    hash160(data::Vector{UInt8})
Cálculo padrão Bitcoin: RIPEMD160(SHA256(data))
"""
function hash160(data::Vector{UInt8})::Vector{UInt8}
    return ripemd160(sha256(data))
end

"""
    priv_to_pub_compressed(priv_key::BigInt)
Deriva a chave pública comprimida (33 bytes) a partir da chave privada (BigInt).
"""
function priv_to_pub_compressed(priv_key::BigInt)::Vector{UInt8}
    pubkey = priv_key * Secp256k1.G
    return Secp256k1.serialize(pubkey, compressed=true)
end

function big_to_32bytes(n::BigInt)::Vector{UInt8}
    bytes = zeros(UInt8, 32)
    temp = copy(n)
    for i in 32:-1:1
        bytes[i] = UInt8(temp % 256)
        temp ÷= 256
    end
    return bytes
end

"""
    serialize_compressed_batch(points_affine::Vector{Tuple{BigInt, BigInt}})
Serializa um lote de pontos (X, Y) no formato comprimido do Bitcoin (33 bytes).
Otimizado para evitar alocações excessivas.
"""
function serialize_compressed_batch(points_affine::Vector{Tuple{BigInt, BigInt}})::Vector{Vector{UInt8}}
    n = length(points_affine)
    out = Vector{Vector{UInt8}}(undef, n)
    for i in 1:n
        x, y = points_affine[i]
        res = Vector{UInt8}(undef, 33)
        res[1] = iseven(y) ? 0x02 : 0x03
        
        # X coord (32 bytes) - Conversão direta e performática
        temp = x
        for j in 33:-1:2
            res[j] = UInt8(temp & 0xFF)
            temp >>= 8
        end
        out[i] = res
    end
    return out
end

"""
    serialize_uncompressed_batch(points_affine::Vector{Tuple{BigInt, BigInt}})
Serializa um lote de pontos (X, Y) no formato não-comprimido (65 bytes).
Formato: 0x04 + X (32 bytes) + Y (32 bytes).
"""
function serialize_uncompressed_batch(points_affine::Vector{Tuple{BigInt, BigInt}})::Vector{Vector{UInt8}}
    n = length(points_affine)
    out = Vector{Vector{UInt8}}(undef, n)
    for i in 1:n
        x, y = points_affine[i]
        res = Vector{UInt8}(undef, 65)
        res[1] = 0x04
        
        # X coord (32 bytes)
        tx = x
        for j in 33:-1:2
            res[j] = UInt8(tx & 0xFF)
            tx >>= 8
        end
        
        # Y coord (32 bytes)
        ty = y
        for j in 65:-1:34
            res[j] = UInt8(ty & 0xFF)
            ty >>= 8
        end
        out[i] = res
    end
    return out
end

"""
    base58_to_hash160(addr::String)
Decodifica um endereço Bitcoin Base58 para os 20 bytes do Hash160.
Remove o prefixo de rede (0x00) e o checksum (4 bytes).
"""
function base58_to_hash160(addr::String)::Vector{UInt8}
    ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    value = BigInt(0)
    for c in addr
        idx = findfirst(==(c), ALPHABET)
        isnothing(idx) && error("Caractere inválido no endereço Base58")
        value = value * 58 + (idx - 1)
    end
    
    # Converter para bytes
    bytes = Vector{UInt8}()
    while value > 0
        push!(bytes, UInt8(value % 256))
        value ÷= 256
    end
    
    # Bitcoin usa big-endian, então invertemos e adicionamos zeros à esquerda se necessário
    reverse!(bytes)
    
    # Um endereço padrão '1...' tem 25 bytes: [1 byte prefixo][20 bytes hash][4 bytes checksum]
    # Se o endereço for curto, precisamos preencher com zeros o prefixo
    while length(bytes) < 25
        pushfirst!(bytes, 0x00)
    end
    
    return bytes[2:21] # Retorna apenas os 20 bytes do hash
end

function hex_to_bytes(hex::String)::Vector{UInt8}
    clean_hex = startswith(hex, "0x") ? hex[3:end] : hex
    # Preenche com zero à esquerda se for ímpar
    if length(clean_hex) % 2 != 0
        clean_hex = "0" * clean_hex
    end
    return hex2bytes(clean_hex)
end

function bytes_to_hex(bytes::Vector{UInt8})::String
    return bytes2hex(bytes)
end

end # module
