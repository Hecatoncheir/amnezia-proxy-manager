#!/usr/bin/env bash
set -euo pipefail
mkdir -p dist
bundle=apps/desktop/build/linux/x64/release/bundle
test -x "$bundle/amnezia_proxy_manager"
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT
tar -C "$bundle" -czf "$archive" .
cat packaging/linux-header.sh "$archive" > dist/AmneziaProxyManager-linux-x64.run
chmod +x dist/AmneziaProxyManager-linux-x64.run
probe=$(mktemp -d)
trap 'rm -f "$archive"; rm -rf "$probe"' EXIT
./dist/AmneziaProxyManager-linux-x64.run --extract "$probe"
test -x "$probe/amnezia_proxy_manager"
test -f "$probe/data/flutter_assets/FontManifest.json"
