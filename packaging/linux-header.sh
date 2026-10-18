#!/bin/sh
set -eu
if [ "${1:-}" = "--extract" ]; then
  destination=${2:?Укажите каталог}
  mkdir -p "$destination"
else
  destination="$HOME/.local/opt/amnezia-proxy-manager"
  mkdir -p "$destination"
fi
payload=$(awk '/^__AMNEZIA_PAYLOAD__$/ { print NR+1; exit }' "$0")
tail -n +"$payload" "$0" | tar -xzf - -C "$destination"
if [ "${1:-}" = "--extract" ]; then exit 0; fi
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
cp "$destination/data/flutter_assets/assets/branding/app_icon_256.png" "$HOME/.local/share/icons/hicolor/256x256/apps/io.github.hecatoncheir.amnezia_proxy_manager.png"
ln -sf "$destination/amnezia_proxy_manager" "$HOME/.local/bin/amnezia-proxy-manager"
cat > "$HOME/.local/share/applications/io.github.hecatoncheir.amnezia_proxy_manager.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=Amnezia Proxy Manager
Icon=$destination/data/flutter_assets/assets/branding/app_icon.png
Exec="$destination/amnezia_proxy_manager"
Terminal=false
Categories=Network;
ENTRY
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$HOME/.local/share/applications" || true
fi
printf '%s\n' "Приложение установлено: $destination" "Запуск: $HOME/.local/bin/amnezia-proxy-manager"
exit 0
__AMNEZIA_PAYLOAD__
