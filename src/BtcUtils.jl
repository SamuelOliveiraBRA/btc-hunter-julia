# btc_utils.jl
# Requer que src/Base58.jl seja incluído antes deste arquivo.

module BtcUtils

using SHA, HTTP, JSON, Printf, Dates
using ..Base58

export generate_wif, get_balance, save_found_key, hash160_to_address

const VERSION_BYTE_MAINNET = 0x80
const ADDR_VERSION_MAINNET = 0x00

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

"""
    save_found_key(puzzle_id::Int, addr::String, pub_hex::String, pk_hex::String, wif::String)
Salva a chave encontrada no arquivo outputs/encontradas.txt com formatação padronizada.
"""
function save_found_key(puzzle_id::Int, addr::String, pub_hex::String, pk_hex::String, wif::String)
    timestamp = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM")
    mkpath("outputs")
    open("outputs/encontradas.txt", "a") do f
        println(f, "$timestamp Puzzle #$puzzle_id" * "-"^67)
        println(f, "Carteira:  $addr")
        println(f, "Public Key: $pub_hex")
        println(f, "Private Key:  $pk_hex")
        println(f, "WIF:  $wif\n")
    end
end

"""
    hash160_to_address(h160::Vector{UInt8}) -> String
Converte Hash160 para endereço Bitcoin (P2PKH Mainnet).
"""
function hash160_to_address(h160::Vector{UInt8})::String
    extended = vcat(UInt8[ADDR_VERSION_MAINNET], h160)
    checksum = _sha256d(extended)[1:4]
    return Base58.encode(vcat(extended, checksum))
end

end # module BtcUtils
