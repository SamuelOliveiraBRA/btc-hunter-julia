module Engines

# ═══════════════════════════════════════════════════════════════════
# Engines.jl — Despachante de Motores Multi-plataforma
# ═══════════════════════════════════════════════════════════════════

export BitCrackEngine, BSGSEngine, GpuEngine

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
using ..SecpOptimized
using ..GpuCrypto

# 3. Carregar Motores Específicos
if IS_MAC
    include("bitcrack/bitcrack_mac.jl")
elseif IS_WINDOWS
    include("bitcrack/bitcrack_win.jl")
else
    include("bitcrack/bitcrack_linux.jl")
end

# Motores Originais / Cross-platform
include("../BSGSEngine.jl")
include("../scanner/GpuScanner.jl") # Keyhunter

const GpuEngine = GpuScanner # Alias amigável

end # module
