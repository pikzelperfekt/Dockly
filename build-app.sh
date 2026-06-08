#!/bin/bash
# Builds Dockly and assembles a proper .app bundle (with icon) into ./dist.
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# Optional variant: DOCKLY_SUFFIX (e.g. "-Ventura") names the app, and
# DOCKLY_DEFINES (e.g. "-Xswiftc -DDOCKLY_VENTURA") passes extra compiler flags.
APP="dist/Dockly${DOCKLY_SUFFIX:-}.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
CONFIG="${1:-release}"

# Universal binary so it runs on both Apple Silicon and Intel Macs.
ARCHS="--arch arm64 --arch x86_64"
echo "▶ Building ($CONFIG, universal)${DOCKLY_SUFFIX:+ [$DOCKLY_SUFFIX]}…"
swift build -c "$CONFIG" $ARCHS ${DOCKLY_DEFINES:-}
BIN="$(swift build -c "$CONFIG" $ARCHS --show-bin-path)/Dockly"

echo "▶ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/Dockly"
cp Info.plist "$CONTENTS/Info.plist"

# ---- Generate the app icon ----
echo "▶ Generating icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC_PNG="$(mktemp -d)/icon-1024.png"

cat > "$(dirname "$SRC_PNG")/gen.swift" <<'SWIFT'
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpaceCreateDeviceRGB()
func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Squircle clip
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 230, yRadius: 230)
bgPath.addClip()

// Vivid diagonal background gradient (blue → purple → pink)
let bg = CGGradient(colorsSpace: cs, colors: [
    col(0.23, 0.45, 0.96),
    col(0.55, 0.27, 0.93),
    col(0.92, 0.27, 0.58)
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Soft top highlight
let hi = CGGradient(colorsSpace: cs, colors: [
    col(1, 1, 1, 0.22), col(1, 1, 1, 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(hi, startCenter: CGPoint(x: size*0.5, y: size*0.92), startRadius: 0,
                       endCenter: CGPoint(x: size*0.5, y: size*0.92), endRadius: size*0.6, options: [])

// Black notch pill hanging from the top — rounded bottom corners
let pillW = 600.0, pillH = 300.0, r = 90.0
let pillX = (size - pillW) / 2
let topY = size, botY = size - pillH
let p = CGMutablePath()
p.move(to: CGPoint(x: pillX, y: topY))
p.addLine(to: CGPoint(x: pillX + pillW, y: topY))
p.addLine(to: CGPoint(x: pillX + pillW, y: botY + r))
p.addQuadCurve(to: CGPoint(x: pillX + pillW - r, y: botY), control: CGPoint(x: pillX + pillW, y: botY))
p.addLine(to: CGPoint(x: pillX + r, y: botY))
p.addQuadCurve(to: CGPoint(x: pillX, y: botY + r), control: CGPoint(x: pillX, y: botY))
p.closeSubpath()
ctx.setShadow(offset: .zero, blur: 40, color: col(0, 0, 0, 0.4))
ctx.addPath(p); ctx.setFillColor(col(0.04, 0.04, 0.06)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Bright accent rim hugging the pill's bottom (Dockly's glowing edge)
ctx.saveGState()
ctx.addPath(p); ctx.replacePathWithStrokedPath(); ctx.clip()
let accent = CGGradient(colorsSpace: cs, colors: [
    col(0.30, 0.85, 1.0), col(0.62, 0.45, 1.0), col(1.0, 0.42, 0.72)
] as CFArray, locations: [0, 0.5, 1])!
ctx.setLineWidth(22)
ctx.drawLinearGradient(accent, start: CGPoint(x: pillX, y: botY),
                       end: CGPoint(x: pillX + pillW, y: botY + 60), options: [])
ctx.restoreGState()

// Three equalizer bars INSIDE the notch pill (centered in its black area)
let heights = [86.0, 150.0, 112.0]
let bw = 46.0, gap = 40.0
let totalW = bw * 3 + gap * 2
var bx = (size - totalW) / 2
let baseY = botY + 60          // sit above the pill's rounded bottom, inside it
for h in heights {
    let bar = CGPath(roundedRect: CGRect(x: bx, y: baseY, width: bw, height: h),
                     cornerWidth: bw/2, cornerHeight: bw/2, transform: nil)
    ctx.addPath(bar); ctx.setFillColor(col(1, 1, 1, 0.95)); ctx.fillPath()
    bx += bw + gap
}

img.unlockFocus()
if let tiff = img.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
SWIFT

swift "$(dirname "$SRC_PNG")/gen.swift" "$SRC_PNG"

for s in 16 32 64 128 256 512 1024; do
    sips -z $s $s "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
# Retina @2x variants
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET/icon_64x64.png"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

# Copy entitlements reference (informational)
[ -f Dockly.entitlements ] && cp Dockly.entitlements "$RES/Dockly.entitlements" || true

# ---- Embed Sparkle.framework (auto-updates) ----
SPARKLE_FW="$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -type d 2>/dev/null | head -1)"
if [ -n "$SPARKLE_FW" ]; then
    echo "▶ Embedding Sparkle.framework…"
    FW_DEST="$CONTENTS/Frameworks"
    mkdir -p "$FW_DEST"
    rm -rf "$FW_DEST/Sparkle.framework"
    cp -R "$SPARKLE_FW" "$FW_DEST/Sparkle.framework"
    # Make sure the executable can find it.
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/Dockly" 2>/dev/null || true
else
    echo "  (Sparkle.framework not found — auto-updates won't work)"
fi

# ---- Code signing ----
# Use a Developer ID identity if CODESIGN_IDENTITY is set (enables notarization);
# otherwise ad-hoc. Sign inner code (Sparkle's XPC services + framework) first.
SIGN_ID="${CODESIGN_IDENTITY:--}"
echo "▶ Code signing (${SIGN_ID})…"
SIGN_FLAGS="--force --options runtime --timestamp"
[ "$SIGN_ID" = "-" ] && SIGN_FLAGS="--force"   # ad-hoc: no hardened runtime/timestamp
if [ -n "$SPARKLE_FW" ]; then
    # Sign Sparkle's nested helpers from the inside out.
    find "$CONTENTS/Frameworks/Sparkle.framework" \
        \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "Updater" \) -print0 2>/dev/null \
        | while IFS= read -r -d '' item; do codesign $SIGN_FLAGS --sign "$SIGN_ID" "$item" 2>/dev/null || true; done
    codesign $SIGN_FLAGS --sign "$SIGN_ID" "$CONTENTS/Frameworks/Sparkle.framework" 2>/dev/null || true
fi
codesign $SIGN_FLAGS --sign "$SIGN_ID" "$MACOS/Dockly" 2>/dev/null || true
codesign $SIGN_FLAGS --sign "$SIGN_ID" "$APP" 2>/dev/null || echo "  (codesign skipped)"

echo "✅ Built $APP"
echo "   Run:  open \"$APP\"   |   Install: drag to /Applications"
