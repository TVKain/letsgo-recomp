#!/usr/bin/env bash
# publicar_jogo.sh (make jogo): copies the current build (build/lasrecomp.exe + build/lasgame.dll) to build/jogo/, the
# copy for playing. That way you can rebuild and test in build/ while the game is open (the exe in use is locked on
# Windows). Run it only with the game closed and with a build that has already been validated (tools/repro.sh).
# It also takes the MSYS2 DLLs the exe needs and the icon: build/jogo/lasrecomp.exe also opens with a double click
# (without MSYS2 on the PATH); the runtime finds the extracted/ folder two folders up (runtime/paths.c).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH"
dest=${1:-build/jogo}  # (another folder: a test copy)
mkdir -p "$dest"
cp build/lasrecomp.exe "$dest/lasrecomp.exe"
cmp -s build/lasgame.dll "$dest/lasgame.dll" 2>/dev/null || cp build/lasgame.dll "$dest/lasgame.dll"
cp build/lasgame.dll.id "$dest/lasgame.dll.id"  # (the runtime refuses a game library without its matching .id)
ldd build/lasrecomp.exe | awk '/ucrt64/ {print $3}' | sort -u | while read -r dll; do cp -u "$dll" "$dest/"; done
cp docs/icon/icon_1024.png "$dest/icon.png"  # (window icon)
cp -u third_party/fidelityfx/bin/amd_fidelityfx_vk.dll "$dest/"  # (FSR 3.1; without it, FSR 1)
echo "$dest updated: $(date "+%d/%m %H:%M")" | tee "$dest/versao.txt"
