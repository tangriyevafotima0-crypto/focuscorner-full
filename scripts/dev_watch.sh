#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "👀 [DEV WATCHER] Sources/FocusCorner ichidagi o'zgarishlar kuzatilmoqda..."
echo "   Har safar .swift fayl saqlanganda avtomatik qayta yig'iladi (To'xtatish: Ctrl+C)"

LAST_HASH=""

while true; do
    CURRENT_HASH="$(find "$PROJECT_ROOT/Sources" -name "*.swift" -exec stat -f "%m %N" {} + 2>/dev/null | shasum || true)"
    if [[ -n "$LAST_HASH" ]] && [[ "$CURRENT_HASH" != "$LAST_HASH" ]]; then
        echo ""
        echo "⚡ O'zgarish aniqlandi! Dev Channel qayta yig'ilmoqda..."
        "$SCRIPT_DIR/run.sh" --dev || echo "⚠️ Kompilyatsiya xatosi — kodni tekshiring."
    fi
    LAST_HASH="$CURRENT_HASH"
    sleep 2
done
