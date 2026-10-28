#!/usr/bin/env bash
set -euo pipefail

# Smooth Channel Switcher & Updater (dev | release)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-release}"

if [[ "$MODE" == "dev" ]]; then
    exec "$SCRIPT_DIR/run.sh" --dev
else
    exec "$SCRIPT_DIR/run.sh" --release
fi
