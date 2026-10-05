#!/bin/sh
# Serwer dedykowany Minecraft Lua (Linux / macOS), bez okna gry.
# Przyklad:  ./server.sh --world=serwer --port=25565
# Opcje: --world=Nazwa --port=25565 --seed=123 --mode=survival|creative
#        --difficulty=0-3 --max=8
# Komendy w terminalu: help, list, say <tekst>, kick <nick>, save, stop
cd "$(dirname "$0")" || exit 1

if command -v love >/dev/null 2>&1; then
  LOVE=love
elif [ -x ./love/squashfs-root/AppRun ]; then
  LOVE=./love/squashfs-root/AppRun
elif [ -x ./love/love ]; then
  LOVE=./love/love
else
  echo "Nie znaleziono LOVE 11.5."
  echo "Ubuntu/Debian:  sudo apt install love"
  echo "albo AppImage:  pobierz love-11.5-x86_64.AppImage do folderu love/, potem"
  echo "                cd love && chmod +x love-11.5-x86_64.AppImage && ./love-11.5-x86_64.AppImage --appimage-extract"
  exit 1
fi

exec "$LOVE" game --server "$@"
