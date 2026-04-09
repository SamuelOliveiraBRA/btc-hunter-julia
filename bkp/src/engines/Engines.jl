module Engines

# ═══════════════════════════════════════════════════════════════════
# Engines.jl — Despachante de Motores Multi-plataforma
# ═══════════════════════════════════════════════════════════════════

export BitCrackEngine, KeyhunterEngine, SecpEngine

# 1. Detectar Plataforma
const IS_MAC     = Sys.isapple()
const IS_WINDOWS = Sys.iswindows()
const IS_LINUX   = Sys.islinux()

# 2. Importar dependências do nível superior (src/)
using ..ConfigModule
using ..FastField
using ..FastSecp
using ..BtcCrypto
using ..CheckpointManager
using ..MultiTarget
using ..BtcUtils

# 2. Carregar Motores Específicos
if IS_MAC
    include("secp/secp_mac.jl")
    include("bitcrack/bitcrack_mac.jl")
    include("keyhunter/keyhunter_mac.jl")
elseif IS_WINDOWS
    include("secp/secp_win.jl")
    include("bitcrack/bitcrack_win.jl")
    include("keyhunter/keyhunter_win.jl")
else # Linux ou outro
    include("secp/secp_linux.jl")
    include("bitcrack/bitcrack_linux.jl")
    include("keyhunter/keyhunter_linux.jl")
end

end # module
