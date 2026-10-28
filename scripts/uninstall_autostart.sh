#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="$HOME/Library/LaunchAgents/com.focuscorner.overlay.plist"
BIN_DIR="$HOME/.focus_corner/bin"

echo "Unregistering FocusCorner LaunchAgent..."
if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
fi

pkill -x "FocusCorner" 2>/dev/null || true
rm -rf "$BIN_DIR"

echo "✅ FocusCorner autostart o'chirildi."
echo "🛡  Sizning ~/.focus_corner/history.md va barcha JSON ma'lumotlaringiz daxlsiz saqlab qolindi."
