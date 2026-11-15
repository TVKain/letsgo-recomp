#!/usr/bin/env bash
# repro.sh <name> [frames to capture] [VAR=value ...]: a deterministic reproduction from a save.
#
# Loads a COPY of the save (save/ stays untouched) into build/test-save, ignores the real controller and presses A only
# at the mapped moments (controller selection, confirmation, title, continue). From frame ~1150 on the game is in
# gameplay (Route 1). Output: logs/repro-<name>.log and build/repro/<name>/frame_N.png (+ contact.png).
# One test at a time: they all use build/frames and build/test-save.
#
# Examples: tools/repro.sh base 1300,1400
#           tools/repro.sh palette 1300,1400 LARECOMP_VK_SKIN_IDENTITY=1
#           EXE=./build/jogo/lasrecomp.exe tools/repro.sh game 1400   (the copy made by make jogo)
#           RENDERDOC=1 tools/repro.sh rdc 1300 LARECOMP_RENDERDOC_AT=1290   (capture in build/rdc/)
#           SAVE="$HOME/Downloads/savedata.bin" tools/repro.sh other 1400   (another save, copied)
# Turbo (default): LARECOMP_FPS=0, without the 30 fps cap. The logic advances one step per frame, so the same frames
# arrive ~4x faster and the scripts (counted in frames) still hold: scenery, camera and positions come out identical;
# only idle animations tied to real time end up in another phase. TURBO=0 goes back to real pace (measuring fps, audio).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH"

name=${1:?test name}
shots=${2:-1400}
shift $(( $# >= 2 ? 2 : 1 ))

rm -rf build/test-save "build/repro/$name"
rm -f build/frames/*.png  # (files only: a removed folder still open somewhere stays "delete pending" and vanishes later)
[ -n "${RENDERDOC:-}" ] && rm -rf build/rdc && mkdir -p build/rdc
mkdir -p build/test-save "build/repro/$name" logs build/frames
# SAVE=<savedata.bin or a save folder>: another save (copied too; the player's save/ stays untouched)
if [ -f "${SAVE:-}" ]; then mkdir -p build/test-save/save_0 && cp "$SAVE" build/test-save/save_0/savedata.bin
else cp -r "${SAVE:-save}"/* build/test-save/; fi

last=${shots##*,}
start=$(date +%s)
(   # the game itself is this background process (exec, no env wrapper): its Windows pid is the one killed below
    [ "${TURBO:-1}" = 0 ] || export LARECOMP_FPS=0
    export LARECOMP_INPUT="400:A:6,500:A:6,1150:A:6,1300:A:6" LARECOMP_NO_USER_INPUT=1 \
        LARECOMP_SAVE_DIR=build/test-save LARECOMP_NO_AUDIO=1 LARECOMP_SHOT_AT="$shots"
    for kv in "$@"; do export "$kv"; done
    if [ -n "${RENDERDOC:-}" ]; then  # under RenderDoc: LARECOMP_RENDERDOC_AT=<frame> picks the frame (build/rdc/)
        exec "/c/Program Files/RenderDoc/renderdoccmd.exe" capture -w -d "$(cygpath -w "$PWD")" ./build/lasrecomp.exe extracted --play             > "logs/repro-$name.log" 2>&1
    fi
    exec "${EXE:-./build/lasrecomp.exe}" extracted --play > "logs/repro-$name.log" 2>&1
) &
pid=$!
last_png=$(printf "build/frames/frame_%05d.png" "$last")
for _ in $(seq 1 "${WAIT:-240}"); do  # (WAIT=<seconds>: how long to wait for the last frame; long scenes need more)
    [ -f "$last_png" ] && break
    grep -q "FATAL\|exception c0" "logs/repro-$name.log" && { echo "CRASH: see logs/repro-$name.log"; break; }
    sleep 1
done
sleep 1  # (the screenshot file is written; let the log catch up)
if [ -n "${RENDERDOC:-}" ]; then  # the capture is written in the background: wait until its size settles
    for _ in $(seq 1 120); do
        if ls build/rdc/*.rdc >/dev/null 2>&1; then
            s1=$(cat build/rdc/*.rdc | wc -c); sleep 5; [ "$s1" = "$(cat build/rdc/*.rdc | wc -c)" ] && break
        else sleep 1; fi
    done
    ls -la build/rdc/
fi
winpid=$(cat "/proc/$pid/winpid" 2>/dev/null || true)
if [ -n "$winpid" ]; then taskkill //F //T //PID "$winpid" >/dev/null 2>&1 || true; else kill "$pid" 2>/dev/null || true; fi
# The runtime re-executes itself when the guest address range is taken (runtime/main.c reserve_guest_space): the game
# is then outside the killed tree. Stop the copies of this exe started since this test began - never older ones (the
# player's game).
exe_win=$(cygpath -w "$(realpath "${EXE:-./build/lasrecomp.exe}")")
powershell.exe -NoProfile -Command "\$t = [DateTimeOffset]::FromUnixTimeSeconds($start).LocalDateTime; Get-CimInstance Win32_Process -Filter \"Name='lasrecomp.exe'\" | Where-Object { \$_.ExecutablePath -eq '$exe_win' -and \$_.CreationDate -ge \$t } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1 || true
wait "$pid" 2>/dev/null || true
cp build/frames/*.png "build/repro/$name/" 2>/dev/null || true
FFMPEG=ffmpeg ./.venv/Scripts/python tools/contact_sheet.py "build/repro/$name/contact.png" build/repro/"$name"/frame_*.png >/dev/null
echo "build/repro/$name/contact.png"
