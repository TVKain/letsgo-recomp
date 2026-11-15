#!/usr/bin/env bash
# trace_run.sh <name> <last frame> [VAR=value ...]: runs the research build (build/trace) straight on the capture route.
# The same capture route as repro.sh (an encounter around frame 1750-1810); LARECOMP_GAME_LIB points at the tracing DLL
# (repro.sh does not pass that variable on reliably). Output: logs/repro-<name>.log and build/frames.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH"
name=${1:?name}; last=${2:?last frame}; shift 2
rm -rf build/test-save; rm -f build/frames/*.png; mkdir -p build/test-save build/frames logs
cp -r save/* build/test-save/
IN="400:A:6,500:A:6,1150:A:6,1300:A:6,1400:STICK_LEFT:300,1700:STICK_DOWN:120,1830:STICK_LEFT:150,1990:STICK_DOWN:100"
(
    [ "${TURBO:-1}" = 0 ] || export LARECOMP_FPS=0
    export LARECOMP_INPUT="$IN" LARECOMP_NO_USER_INPUT=1 LARECOMP_SAVE_DIR=build/test-save LARECOMP_NO_AUDIO=1 \
        LARECOMP_SHOT_AT="$last" LARECOMP_GAME_LIB="$(cygpath -w "$PWD/build/trace/lasgame.dll")"
    for kv in "$@"; do export "$kv"; done
    exec ./build/trace/lasrecomp.exe extracted --play > "logs/repro-$name.log" 2>&1
) &
for _ in $(seq 1 900); do [ -f "$(printf 'build/frames/frame_%05d.png' "$last")" ] && break; sleep 1; done
sleep 2
taskkill //F //IM lasrecomp.exe >/dev/null 2>&1
mkdir -p "build/repro/$name"; cp build/frames/*.png "build/repro/$name/" 2>/dev/null
ls "build/repro/$name" | head -20
