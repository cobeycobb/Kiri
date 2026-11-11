#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p .build
swiftc -swift-version 5 -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$PWD/.build/module-cache" Sources/Kiri/*.swift -o .build/Kiri
BIN_DIR="$PWD/.build"
APP="$PWD/dist/Kiri.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Kiri" "$APP/Contents/MacOS/Kiri"
cp Assets/Kiri.png "$APP/Contents/Resources/Kiri.png"
ICONSET="$PWD/.build/Kiri.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/Kiri.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/Kiri.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Kiri.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Kiri</string>
<key>CFBundleIdentifier</key><string>com.kiri.app</string>
<key>CFBundleName</key><string>Kiri</string>
<key>CFBundleDisplayName</key><string>Kiri</string>
<key>CFBundleIconFile</key><string>Kiri</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Kiri reads the area you select and copies its text to your clipboard. Images stay on your Mac and are not saved.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf '\nBuilt %s\n' "$APP"
