#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

desk_package_app="$PWD/dist/Desk Control.app"
if [[ ! -d "$desk_package_app" ]]; then
    print -u2 -- "请先运行 ./scripts/build.sh 构建发布版。"
    exit 1
fi
codesign --verify --deep --strict "$desk_package_app"
desk_package_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$desk_package_app/Contents/Info.plist")"
if [[ ! "$desk_package_version" =~ '^[0-9]+([.][0-9]+)*$' ]]; then
    print -u2 -- "应用版本号无效：$desk_package_version"
    exit 1
fi

mkdir -p "$PWD/dist"
desk_package_output="$PWD/dist/Desk-Control-$desk_package_version.dmg"
desk_package_stage="$(mktemp -d "${TMPDIR:-/tmp}/desk-control-dmg-stage.XXXXXX")"
desk_package_mount=""
desk_package_is_mounted=false
desk_package_cleanup() {
    if [[ "$desk_package_is_mounted" == true ]]; then
        hdiutil detach "$desk_package_mount" -quiet || true
    fi
    if [[ -n "$desk_package_mount" ]]; then
        rmdir "$desk_package_mount" 2>/dev/null || true
    fi
    rm -rf -- "$desk_package_stage"
}
trap desk_package_cleanup EXIT

ditto "$desk_package_app" "$desk_package_stage/Desk Control.app"
ln -s /Applications "$desk_package_stage/Applications"
codesign --verify --deep --strict "$desk_package_stage/Desk Control.app"
hdiutil create -quiet -ov -volname "Desk Control" -srcfolder "$desk_package_stage" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$desk_package_output"
hdiutil verify -quiet "$desk_package_output"

desk_package_mount="$(mktemp -d "${TMPDIR:-/tmp}/desk-control-dmg-check.XXXXXX")"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$desk_package_mount" "$desk_package_output"
desk_package_is_mounted=true
codesign --verify --deep --strict "$desk_package_mount/Desk Control.app"
[[ "$(readlink "$desk_package_mount/Applications")" == /Applications ]]
cmp "$desk_package_app/Contents/MacOS/DeskControl" "$desk_package_mount/Desk Control.app/Contents/MacOS/DeskControl"
cmp "$desk_package_app/Contents/Info.plist" "$desk_package_mount/Desk Control.app/Contents/Info.plist"
cmp "$desk_package_app/Contents/Resources/AppIcon.icns" "$desk_package_mount/Desk Control.app/Contents/Resources/AppIcon.icns"
hdiutil detach -quiet "$desk_package_mount"
desk_package_is_mounted=false
print -r -- "DMG 已生成并通过挂载校验：$desk_package_output"
