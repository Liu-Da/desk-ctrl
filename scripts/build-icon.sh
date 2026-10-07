#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

desk_icon_source="$PWD/Resources/AppIcon.png"
desk_icon_stage="$(mktemp -d "${TMPDIR:-/tmp}/desk-control-icon.XXXXXX")"
trap 'rm -rf -- "$desk_icon_stage"' EXIT
desk_icon_set="$desk_icon_stage/AppIcon.iconset"
mkdir -p "$desk_icon_set"

desk_icon_resize() {
    sips -z "$1" "$1" "$desk_icon_source" --out "$desk_icon_set/$2" >/dev/null
}

desk_icon_resize 16 icon_16x16.png
desk_icon_resize 32 icon_16x16@2x.png
desk_icon_resize 32 icon_32x32.png
desk_icon_resize 64 icon_32x32@2x.png
desk_icon_resize 128 icon_128x128.png
desk_icon_resize 256 icon_128x128@2x.png
desk_icon_resize 256 icon_256x256.png
desk_icon_resize 512 icon_256x256@2x.png
desk_icon_resize 512 icon_512x512.png
desk_icon_resize 1024 icon_512x512@2x.png

iconutil -c icns "$desk_icon_set" -o "$PWD/Resources/AppIcon.icns"
print -r -- "已生成应用图标：$PWD/Resources/AppIcon.icns"
