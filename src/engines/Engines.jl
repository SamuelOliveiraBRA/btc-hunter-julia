module Engines

# ═══════════════════════════════════════════════════════════════════
# Engines.jl — Despachante de Motores Multi-plataforma
# ═══════════════════════════════════════════════════════════════════

export BitCrackEngine, BitCrackLegacy, BSGSEngine, GpuEngine, SecpOptimized

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
# Motor Nativo Otimizado (M4/Mac / CPU Principal)
include("bitcrack/bitcrack_mac.jl")

# Motores Originais / Cross-platform
include("../BitCrackEngine.jl")     # Renomeado internamente para BitCrackLegacy
include("../BSGSEngine.jl")
include("../scanner/GpuScanner.jl") # Keyhunter

const GpuEngine = GpuScanner # Alias amigável

end # module
