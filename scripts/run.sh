#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# FocusCorner v6.5 (RPA 3-Day Matrix, Gu No-Error 20%, Height Fix & Custom Logo)
# Smart Installer, Native .app Bundler with Custom AppIcon.icns & Safe Migration
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
echo "🚀 FocusCorner v6.5 (RPA 3-Kunlik Jadval & Gu No-Error 20%) — O'rnatish"
echo "   Kanal (Channel): $CHANNEL | Manba: $PROJECT_ROOT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. FOYDALANUVCHI MA'LUMOTLARINI VA HISTORY.MD / RPA ARXIVINI 100% HIMOYA QILISH
mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$BIN_DIR" "$CHANNELS_DIR/dev" "$CHANNELS_DIR/release" "$ROLLBACK_DIR"

if [[ -f "$DATA_DIR/history.md" ]] || [[ -f "$DATA_DIR/tasks.json" ]] || [[ -f "$DATA_DIR/rules.json" ]]; then
    SNAPSHOT_PATH="$BACKUP_DIR/snapshot_$TIMESTAMP"
    mkdir -p "$SNAPSHOT_PATH"
    for f in "history.md" "rules.json" "rpa_archive.json" "rpa_history.md" "tasks.json" "sat_tracker.json" "exacc.json" "settings.json" "timer_config.json"; do
        if [[ -f "$DATA_DIR/$f" ]]; then
            cp -p "$DATA_DIR/$f" "$SNAPSHOT_PATH/$f"
        fi
    done
    if [[ -d "$DATA_DIR/notebook" ]]; then cp -R "$DATA_DIR/notebook" "$SNAPSHOT_PATH/notebook" 2>/dev/null || true; fi
    echo "🛡  Ma'lumotlar himoyasi: history.md, RPA Arxiv, Bloknot va barcha JSON sozlamalar zahiralandi."
    ls -dt "$BACKUP_DIR"/snapshot_* 2>/dev/null | tail -n +16 | xargs rm -rf 2>/dev/null || true
fi

rm -f "$DATA_DIR"/.*.tmp "$DATA_DIR"/*.tmp 2>/dev/null || true
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

# 5. FAQAT BITTA NATIVE .APP BUNDLE VA MAXSUS LOGO (AppIcon.icns) YARATISH
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

# Generate Native macOS AppIcon.icns using Swift AppKit CoreGraphics
ICONSET_DIR="$DATA_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_ICON_EOF' 2>/dev/null || true
import AppKit

let args = CommandLine.arguments
guard args.count > 1 else { exit(0) }
let iconsetPath = args[1]

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.24
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 1. Deep Sapphire-Navy Squircle Background
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.14, green: 0.44, blue: 0.96, alpha: 1.0),
        CGColor(red: 0.05, green: 0.12, blue: 0.30, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    }
    ctx.restoreGState()

    // 2. Outer Luminous Border
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.45, green: 0.88, blue: 1.0, alpha: 0.85))
    ctx.setLineWidth(max(1.5, s * 0.028))
    ctx.strokePath()
    ctx.restoreGState()

    // 3. Rotated Primeval Aperture Diamond
    ctx.saveGState()
    ctx.translateBy(x: s * 0.5, y: s * 0.5)
    ctx.rotate(by: .pi / 4.0)
    let dSize = s * 0.38
    let dRect = CGRect(x: -dSize / 2, y: -dSize / 2, width: dSize, height: dSize)
    let dPath = CGPath(roundedRect: dRect, cornerWidth: dSize * 0.22, cornerHeight: dSize * 0.22, transform: nil)
    ctx.addPath(dPath)
    ctx.setStrokeColor(CGColor(red: 0.36, green: 0.94, blue: 0.86, alpha: 0.95))
    ctx.setLineWidth(max(1.8, s * 0.055))
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Glowing Center Focus Core
    let coreSize = s * 0.19
    let coreRect = CGRect(x: (s - coreSize) / 2, y: (s - coreSize) / 2, width: coreSize, height: coreSize)
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0.88, green: 0.98, blue: 1.0, alpha: 1.0))
    ctx.fillEllipse(in: coreRect)
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    let img = renderIcon(size: px)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
SWIFT_ICON_EOF

if [[ -d "$ICONSET_DIR" ]]; then
    /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET_DIR"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>6.5.0</string>
    <key>CFBundleShortVersionString</key>
    <string>6.5.0</string>
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

touch "$APP_BUNDLE" 2>/dev/null || true
echo "🍏 Yagona Native ilova va maxsus Logo (AppIcon.icns) o'rnatildi: $APP_BUNDLE"

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
  "version": "v6.5.0-RPANoError"
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
    launchctl load -w "$PLIST_PATH" 2>/dev/null || true
    sleep 0.5
fi

if ! pgrep -x "FocusCorner" >/dev/null 2>&1; then
    nohup "$APP_BUNDLE/Contents/MacOS/FocusCorner" >/dev/null 2>&1 &
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ TAYYOR! FocusCorner v6.5 (3-Kunlik RPA + Gu No-Error 20% + Logo + BugFix) ishlamoqda!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
