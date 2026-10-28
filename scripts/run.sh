#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FocusCorner v5.2 (Terminal & Backup) (Single-Instance + MenuBar App + Dev Studio)
# Smart Installer, Native .app Bundler, Dev/Release Channel & Safe Migration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$SCRIPT_DIR")" == "scripts" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    PROJECT_ROOT="$SCRIPT_DIR"
fi

DATA_DIR="$HOME/.focus_corner"
BACKUP_DIR="$DATA_DIR/backups"
BIN_DIR="$DATA_DIR/bin"
CHANNELS_DIR="$DATA_DIR/channels"
ROLLBACK_DIR="$CHANNELS_DIR/rollback"
PLIST_PATH="$HOME/Library/LaunchAgents/com.focuscorner.overlay.plist"
META_FILE="$DATA_DIR/channel_meta.json"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HUMAN_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

CHANNEL="release"
CLEAN_BUILD_CACHE="true"
AUTOSTART_REGISTER="true"

for arg in "$@"; do
    case "$arg" in
        --dev)
            CHANNEL="dev"
            CLEAN_BUILD_CACHE="false"
            ;;
        --release|--stable)
            CHANNEL="release"
            CLEAN_BUILD_CACHE="true"
            ;;
        --keep-cache)
            CLEAN_BUILD_CACHE="false"
            ;;
        --no-autostart)
            AUTOSTART_REGISTER="false"
            ;;
    esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 FocusCorner v5.2 (Terminal & Backup) Synergy — Yagona Nusxa (Single-Instance) O'rnatish"
echo "   Kanal (Channel): $CHANNEL | Manba: $PROJECT_ROOT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. FOYDALANUVCHI MA'LUMOTLARINI VA HISTORY.MD FAYLINI 100% HIMOYA QILISH
mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$BIN_DIR" "$CHANNELS_DIR/dev" "$CHANNELS_DIR/release" "$ROLLBACK_DIR"

if [[ -f "$DATA_DIR/history.md" ]] || [[ -f "$DATA_DIR/tasks.json" ]] || [[ -f "$DATA_DIR/rules.json" ]]; then
    SNAPSHOT_PATH="$BACKUP_DIR/snapshot_$TIMESTAMP"
    mkdir -p "$SNAPSHOT_PATH"
    for f in "history.md" "rules.json" "tasks.json" "sat_tracker.json" "exacc.json" "settings.json" "timer_config.json"; do
        if [[ -f "$DATA_DIR/$f" ]]; then
            cp -p "$DATA_DIR/$f" "$SNAPSHOT_PATH/$f"
        fi
    done
    if [[ -d "$DATA_DIR/notebook" ]]; then cp -R "$DATA_DIR/notebook" "$SNAPSHOT_PATH/notebook" 2>/dev/null || true; fi
    echo "🛡  Ma'lumotlar himoyasi: history.md, Bloknot (rasm/ovozlar) va barcha JSON sozlamalar zahiralandi."
    ls -dt "$BACKUP_DIR"/snapshot_* 2>/dev/null | tail -n +16 | xargs rm -rf 2>/dev/null || true
fi

rm -f "$DATA_DIR"/.*.tmp "$DATA_DIR"/*.tmp 2>/dev/null || true
if [[ -f "$DATA_DIR/settings.json" ]]; then
    python3 -c "import json, pathlib; p=pathlib.Path('$DATA_DIR/settings.json'); d=json.loads(p.read_text()); d['migratedV5_2Oct18TerminalBackup']=False; p.write_text(json.dumps(d, indent=2))" 2>/dev/null || true
fi
cp "$PROJECT_ROOT/scripts/fc_sync.py" "$BIN_DIR/fc_sync.py" 2>/dev/null || true
chmod +x "$BIN_DIR/fc_sync.py" 2>/dev/null || true

# 2. ROLLBACK BINARY ZAHIRALASH
if [[ -f "$BIN_DIR/FocusCorner" ]]; then
    cp -p "$BIN_DIR/FocusCorner" "$ROLLBACK_DIR/FocusCorner"
fi

# 3. KOMPILYATSIYA
cd "$PROJECT_ROOT"

if [[ "$CHANNEL" == "dev" ]]; then
    echo "🛠  [DEV CHANNEL] Debug rejimida tezkor kompilyatsiya qilinmoqda..."
    swift build
    BUILT_BINARY="$PROJECT_ROOT/.build/debug/FocusCorner"
    cp "$BUILT_BINARY" "$CHANNELS_DIR/dev/FocusCorner"
else
    echo "⚡ [RELEASE CHANNEL] Yuqori unumdorlikdagi Release binary yig'ilmoqda..."
    swift build -c release
    BUILT_BINARY="$PROJECT_ROOT/.build/release/FocusCorner"
    cp "$BUILT_BINARY" "$CHANNELS_DIR/release/FocusCorner"
fi

# 4. BARCHA ESKI VA DUBLIKAT JARAYONLARNI TO'LIQ TO'XTATISH
echo "🔄 Barcha eski FocusCorner nusxalari to'xtatilmoqda..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
for old_plist in "$HOME"/Library/LaunchAgents/*focuscorner*.plist "$HOME"/Library/LaunchAgents/*FocusCorner*.plist; do
    if [[ -f "$old_plist" ]] && [[ "$old_plist" != "$PLIST_PATH" ]]; then
        launchctl unload "$old_plist" 2>/dev/null || true
        rm -f "$old_plist"
    fi
done
killall -9 FocusCorner 2>/dev/null || pkill -9 -x FocusCorner 2>/dev/null || true
sleep 0.4

cp "$BUILT_BINARY" "$BIN_DIR/FocusCorner"
chmod +x "$BIN_DIR/FocusCorner"

# 5. FAQAT BITTA NATIVE .APP BUNDLE YARATISH (DUBLIKATLARNI O'CHIRISH)
rm -rf "$HOME/Applications/FocusCorner.app" 2>/dev/null || true
if [[ -w "/Applications" ]]; then
    APP_BUNDLE="/Applications/FocusCorner.app"
    rm -rf "$APP_BUNDLE" 2>/dev/null || true
else
    mkdir -p "$HOME/Applications"
    APP_BUNDLE="$HOME/Applications/FocusCorner.app"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/FocusCorner" "$APP_BUNDLE/Contents/MacOS/FocusCorner"
chmod +x "$APP_BUNDLE/Contents/MacOS/FocusCorner"

cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FocusCorner</string>
    <key>CFBundleIdentifier</key>
    <string>com.focuscorner.app</string>
    <key>CFBundleName</key>
    <string>FocusCorner</string>
    <key>CFBundleDisplayName</key>
    <string>FocusCorner</string>
    <key>CFBundleVersion</key>
    <string>5.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>5.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>FocusCorner Bloknot ichida ovozli eslatmalar yozib olish uchun mikrofondan foydalanadi.</string>
</dict>
</plist>
EOF

echo "🍏 Yagona Native ilova o'rnatildi: $APP_BUNDLE"

if [[ "$CHANNEL" == "release" ]] && [[ "$CLEAN_BUILD_CACHE" == "true" ]]; then
    echo "🧹 Keraksiz .build kesh fayllari tozalanmoqda..."
    swift package clean || rm -rf "$PROJECT_ROOT/.build"
fi

# 6. DEV STUDIO METADATA YANGILASH
BUILD_COUNT=1
if [[ -f "$META_FILE" ]]; then
    OLD_COUNT=$(python3 -c "import json; print(json.load(open('$META_FILE')).get('buildCount', 0))" 2>/dev/null || echo 0)
    BUILD_COUNT=$((OLD_COUNT + 1))
fi

cat <<EOF > "$META_FILE"
{
  "activeChannel": "$CHANNEL",
  "buildCount": $BUILD_COUNT,
  "lastBuildTime": "$HUMAN_TIME",
  "sourceRepoPath": "$PROJECT_ROOT",
  "version": "v5.2.0-TerminalBackup"
}
EOF

# 7. AUTORUN RO'YXATDAN O'TKAZISH VA FAQAT BITTA NUSXANI ISHGA TUSHIRISH
if [[ "$AUTOSTART_REGISTER" == "true" ]]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.focuscorner.overlay</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BUNDLE/Contents/MacOS/FocusCorner</string>
        <string>--autostart</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
    # launchctl load with RunAtLoad=true automatically starts 1 instance!
    launchctl load -w "$PLIST_PATH" 2>/dev/null || true
    sleep 0.5
fi

# Only start manually if launchctl did not already start it
if ! pgrep -x "FocusCorner" >/dev/null 2>&1; then
    nohup "$APP_BUNDLE/Contents/MacOS/FocusCorner" >/dev/null 2>&1 &
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TAYYOR! Faqat 1 ta yagona FocusCorner v5.2 (Terminal & Backup) ishlamoqda!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
