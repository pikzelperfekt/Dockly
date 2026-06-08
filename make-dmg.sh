#!/bin/bash
# Builds Dockly.app and packages it into a styled .dmg with a drag-to-Applications layout.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# DOCKLY_SUFFIX (e.g. "-Ventura") names the variant; DOCKLY_DEFINES is forwarded
# to build-app.sh for variant compiler flags.
SUFFIX="${DOCKLY_SUFFIX:-}"
VOL="Dockly${SUFFIX}"
APP="dist/Dockly${SUFFIX}.app"
DMG_TMP="dist/Dockly${SUFFIX}-tmp.dmg"
DMG_FINAL="dist/Dockly${SUFFIX}.dmg"

# 1) Build the app (with the fresh icon)
./build-app.sh release

# 2) Generate the DMG background image
BG="$ROOT/dist/.dmg-bg.png"
BG_SWIFT="$(mktemp -d)/bg.swift"
cat > "$BG_SWIFT" <<'SWIFT'
import AppKit
let W = 660.0, H = 420.0
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpaceCreateDeviceRGB()
func col(_ r: Double,_ g: Double,_ b: Double,_ a: Double=1)->CGColor{CGColor(srgbRed:r,green:g,blue:b,alpha:a)}
// Dark branded gradient
let bg = CGGradient(colorsSpace: cs, colors: [col(0.10,0.09,0.16), col(0.05,0.05,0.09)] as CFArray, locations: [0,1])!
ctx.drawLinearGradient(bg, start: CGPoint(x:0,y:H), end: CGPoint(x:W,y:0), options: [])
// Title
let title = "Dockly"
let tAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .bold),
    .foregroundColor: NSColor.white]
title.draw(at: NSPoint(x: 40, y: H - 70), withAttributes: tAttr)
let sub = "Drag Dockly into Applications to install"
let sAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(white: 1, alpha: 0.6)]
sub.draw(at: NSPoint(x: 40, y: H - 96), withAttributes: sAttr)
// Arrow between the two icon slots (icons sit at x≈165 and x≈495, y≈205 from top)
let arrowY = H - 205
let arrow = NSBezierPath()
arrow.lineWidth = 8
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 270, y: arrowY))
arrow.line(to: NSPoint(x: 390, y: arrowY))
NSColor(white: 1, alpha: 0.5).setStroke(); arrow.stroke()
let head = NSBezierPath()
head.lineWidth = 8; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: 365, y: arrowY + 22))
head.line(to: NSPoint(x: 392, y: arrowY))
head.line(to: NSPoint(x: 365, y: arrowY - 22))
NSColor(white: 1, alpha: 0.5).setStroke(); head.stroke()
img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
SWIFT
swift "$BG_SWIFT" "$BG"
echo "▶ Building DMG…"

# 3) Stage contents
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BG" "$STAGE/.background/bg.png"

# 4) Create a read-write DMG sized to fit
rm -f "$DMG_TMP" "$DMG_FINAL"
MB=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -format UDRW -size ${MB}m "$DMG_TMP" >/dev/null

# 5) Mount + lay out icons via Finder
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" | egrep '^/dev/' | head -1 | awk '{print $1}')
sleep 2
osascript <<EOF || echo "  (Finder layout skipped — grant Automation if you want the styled layout)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 120
    set background picture of opts to file ".background:bg.png"
    set position of item "Dockly${SUFFIX}.app" of container window to {165, 200}
    set position of item "Applications" of container window to {495, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
sync

# 6) Finalize: compress to read-only
hdiutil detach "$DEV" >/dev/null || true
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -f "$DMG_TMP"
rm -rf "$STAGE"

echo "✅ Built $DMG_FINAL"
