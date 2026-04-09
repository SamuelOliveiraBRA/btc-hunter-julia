#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  BTC HUNTER JULIA — Lançador Oficial
#  Sempre inicia Julia com o número correto de threads
# ═══════════════════════════════════════════════════════════

JULIA=$(which julia 2>/dev/null || echo "$HOME/.juliaup/bin/julia")
CPUS=$(python3 -c "import json; d=json.load(open('config/settings.json')); print(d.get('cpus', 10))" 2>/dev/null || echo "10")

echo ""
echo "  🚀 BTC Hunter — Iniciando com $CPUS threads..."
echo ""

exec "$JULIA" -t "$CPUS" main.jl "$@"
