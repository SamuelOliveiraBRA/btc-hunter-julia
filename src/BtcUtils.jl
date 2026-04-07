# btc_utils.jl
# Requer que src/Base58.jl seja incluído antes deste arquivo.

module BtcUtils

using SHA, HTTP, JSON, Printf
using ..Base58

export generate_wif, get_balance

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

"""
    get_balance(address::String) -> String
Consulta o saldo de um endereço via blockchain.info (Satoshis -> BTC).
"""
function get_balance(address::String)::String
    isempty(address) && return "0.0000"
    try
        url = "https://blockchain.info/rawaddr/$address"
        response = HTTP.get(url, retry=false, connect_timeout=5)
        data = JSON.parse(String(response.body))
        satoshis = get(data, "final_balance", 0)
        return @sprintf("%.8f", satoshis / 1e8)
    catch
        return "Erro/Off"
    end
end

end # module BtcUtils
