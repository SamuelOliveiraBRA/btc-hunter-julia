# btc_utils.jl
# Requer que src/Base58.jl seja incluído antes deste arquivo.

module BtcUtils

using SHA
using ..Base58

export generate_wif

const VERSION_BYTE_MAINNET = 0x80

# SHA256 duplo — apenas para gerar checksum WIF (não conflita com BtcCrypto)
function _sha256d(data::Vector{UInt8})::Vector{UInt8}
    Vector{UInt8}(SHA.sha256(SHA.sha256(data)))
end

"""
    generate_wif(priv_key::BigInt; compressed=true) -> String
Converte chave privada para formato WIF (Wallet Import Format).
"""
function generate_wif(priv_key::BigInt; compressed::Bool=true)::String
    priv_hex   = lpad(string(priv_key, base=16), 64, "0")
    priv_bytes = hex2bytes(priv_hex)

    extended = compressed ?
        vcat(UInt8[VERSION_BYTE_MAINNET], priv_bytes, UInt8[0x01]) :
        vcat(UInt8[VERSION_BYTE_MAINNET], priv_bytes)

    checksum      = _sha256d(extended)[1:4]
    final_payload = vcat(extended, checksum)
    return Base58.encode(final_payload)
end

end # module BtcUtils
