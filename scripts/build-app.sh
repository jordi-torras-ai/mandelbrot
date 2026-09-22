#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/Mandelbrot.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Mandelbrot" "$app_dir/Contents/MacOS/Mandelbrot"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
