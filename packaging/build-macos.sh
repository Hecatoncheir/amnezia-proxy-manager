#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
app=apps/desktop/build/macos/Build/Products/Release/amnezia_proxy_manager.app
test -d "$app"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/amnezia_proxy_manager.app"
ln -s /Applications "$stage/Applications"
cp "$app/Contents/Resources/AppIcon.icns" "$stage/.VolumeIcon.icns"
xcrun SetFile -a C "$stage"
output="dist/AmneziaProxyManager-macos-$(uname -m).dmg"
hdiutil create -volname "Amnezia Proxy Manager" -srcfolder "$stage" -ov -format UDZO "$output"
hdiutil verify "$output"
