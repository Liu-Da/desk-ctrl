#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
./scripts/build-icon.sh
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Desk Control.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/DeskControl" "$app_dir/Contents/MacOS/DeskControl"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.liuda.desk-control "$app_dir"
print -r -- "已构建：$app_dir"
