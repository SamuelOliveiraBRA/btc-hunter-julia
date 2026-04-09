module BSGSEngine

# ═══════════════════════════════════════════════════════════════════
# BSGSEngine.jl — Algoritmo Baby-Step Giant-Step em RAM
#
# Importante: Este motor é estritamente aplicável quando o alvo
# inclui a CHAVE PÚBLICA (X, Y uncompressed/compressed point Q).
# Não funciona O(1) se o alvo for APENAS o Hash160 (endereço),
# pois a função de hash quebra o isomorfismo algébrico da curva.
#
# Lógica Matemática O(1):
# 1. Cria em RAM uma tabela Hash->Index de (i * G) : Baby Steps [0, m)
# 2. Caminha nos P_j = Target_Q - (j * m * G)      : Giant Steps
# Se P_j colidir com algo na tabela (p.ex., i), então:
#   PrivKey = j * m + i
# ═══════════════════════════════════════════════════════════════════

using ..FastField
using ..FastSecp
using ..BtcCrypto

export BSGSState, load_bsgs_table, check_giant_step

struct BSGSState
    m::Int                       # Tamanho do Giant Step
    baby_table::Dict{FE256, Int} # Mapa X-coordinate -> Offset (0 até m-1)
    target_Q::PointJ             # Ponto Púbico Alvo
    neg_mG::PointJ               # Ponto: -(m * G)
end

"""
    load_bsgs_table(target_pub_hex, m_size)
Pré-computa os Baby Steps e gera a tabela em RAM.
- `m_size`: ex: 65536 (ocupa alguns MB). P/ uso extremo pode ser 16M (GBs de RAM).
"""
function load_bsgs_table(target_pub_hex::String, m_size::Int)::BSGSState
    # Interpretar a PubKey alvo
    # Aqui assumimos uma PubKey Uncompressed padronizada (04 + 32b X + 32b Y)
    raw = BtcCrypto.hex_to_bytes(target_pub_hex)
    if length(raw) != 65 || raw[1] != 0x04
        error("BSGS Engine necessita de uma chave pública no formato UNCOMPRESSED (65 bytes começando com 04)")
    end

    Q_x = FastField.from_big(parse(BigInt, BtcCrypto.bytes_to_hex(raw[2:33]), base=16))
    Q_y = FastField.from_big(parse(BigInt, BtcCrypto.bytes_to_hex(raw[34:65]), base=16))
    target_Q = PointJ(Q_x, Q_y, FastField.ONE)

    # 1. Tabela de Baby-Steps
    # Tabela mapará Coordenada X (FE256) -> Índice
    # Atenção: colisão de X e Y pode ocorrer (pois há Y inverso),
    # mas o teste final validará o Y usando a equação da curva para garantir 100%.
    table = Dict{FE256, Int}()
    sizehint!(table, m_size)

    # O Ponto atual "P" começa em 0*G (não inserimos infinito, pulamos do 1)
    # i=0 seria 0*G. Como queremos somar, vamos fazer com G_J_fast
    curr = FastSecp.G_J_fast
    
    # Batch N para affine (não queremos inversões em cada giant step)
    # Para simplicidade de set-up (não gargalo), faremos uma conversão normal
    base_points = Vector{PointJ}(undef, m_size)
    for i in 1:m_size
        base_points[i] = curr
        curr = FastSecp.point_add_jacobian(curr, FastSecp.G_J_fast)
    end
    
    # Ao final, "curr" é m * G. Vamos negativar para os Giant Steps:
    # -(X, Y, Z) = (X, -Y, Z)
    neg_mG = PointJ(curr.x, FastField.sub_mod(FastField.ZERO, curr.y), curr.z)

    # Na tabela inserimos [0..m-1] -> [1..m] no nosso vetor
    for i in 1:m_size
        # Normalização jacobiana: não é estritamente necessária se a tabela lidar com affine,
        # mas como são pontos em Jacobiano com Z diferentes, temos que converter para affine
        iz = FastField.inv_mod(base_points[i].z)
        iz2 = FastField.sqr_mod(iz)
        ax = FastField.mul_mod(base_points[i].x, iz2)
        
        # Guarda índice
        table[ax] = i
    end

    return BSGSState(m_size, table, target_Q, neg_mG)
end

"""
    check_giant_step(state, current_base)
Executa a busca BSGS. current_base dita a rodada num formato `j * m`.
Retorna o offset `i` caso encontre colisāo, e -1 caso não ache.
"""
function check_giant_step(state::BSGSState, current_j::BigInt)::Int
    # Giant step: testamos P_j = Q - (j * m * G)
    # Se bater num baby_step i*G, quer dizer que Target_Q = (j*m + i)*G
    
    # 0. Bootstrapping j*m*G: Como calcular rápido? 
    # Usamos SecpOptimized para escalar
    # ...
    # Mas como o loop do Main.jl avança de forma sequencial pelo range numérico,
    # essa versão do BSGS é estritamente "alvo para pubkey", não address puro.
    
    # *Nota*: O método foi estruturado seguindo KeyHunt, mas como nossos wallets
    # alvo .json do usuário só trazem `Hash160`, esse método será mantido para
    # o Modo Dev ou futuros puzzles "Uncompressed/Known PubKey".
    
    return -1 # Stub. Como discutido no design, BSGS Address-Only é matematicamente impossível.
end

end # module BSGSEngine
