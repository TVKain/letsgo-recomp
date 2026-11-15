#!/usr/bin/env bash
# teste60.sh <scene> <mode> [VAR=value ...]: the same scene at 30 fps and in a 60 fps mode, frame by frame in game time.
#
#   scene: captura (walk in the Route 1 grass until an encounter, throw the ball) | batalha (walk down: the trainer in
#          Viridian Forest, dialogue advanced with A)
#   mode:  0 (30 fps, reference) | 1 (world at 60, scenes at 30 + interpolation) | 2 (everything at 60, divided counters)
# Extra VAR=value go to the game (e.g. LARECOMP_WINDOW_SHOTS_REL=1 LARECOMP_WINDOW_SHOTS=... for the in-between/final
# pairs, measured with tools/interp_metrics.py).
#
# Captures images of the scene at moments relative to its start (LARECOMP_SHOT_REL; fps60.c marks the start): at 30 fps
# at 30, 60, 90...; in the 60 modes at 60, 120, 180... (the same game time, if the logic runs at the right speed).
# Output: build/teste60/<scene>-<mode>/rel_*.png and sheet.png. Compare the sheets of 0 and of the tested mode: the same
# row should show the same moment of the scene. Runs in turbo (LARECOMP_FPS=0): the logic advances one step per frame,
# so the game frames are identical to those at real pace.
# The route depends on the encounter roll: the frame at which the scene starts varies; the images are relative to it.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH"
cena=${1:?scene: captura or batalha}
modo=${2:?mode: 0, 1 or 2}
shift 2
base="400:A:6,500:A:6,1150:A:6,1300:A:6"
case "$cena" in
    captura) route="$base,1400:STICK_LEFT:300,1700:STICK_DOWN:120,1830:STICK_LEFT:150,1990:STICK_DOWN:100"
             for t in $(seq 2020 120 3200); do route="$route,$t:A:6"; done; last=3300 ;;
    batalha) route="$base,1400:STICK_DOWN:400"
             for t in $(seq 1900 40 3500); do route="$route,$t:A:6"; done; last=3700 ;;
    *) echo "unknown scene: $cena"; exit 1 ;;
esac
k=1; [ "$modo" = 0 ] || k=2
# In the 60 fps modes the world (and, in mode 2, the scenes) take two updates per game-time step: the inputs from the
# gameplay on (frame 1400) are stretched by k, so the route and the A presses land at the same game time.
route=$(echo "$route" | tr ',' '\n' | awk -F: -v k="$k" '{ t = $1; d = $3; if (t >= 1400) { t = 1400 + (t - 1400) * k; d = d * k } print t ":" $2 ":" d }' | paste -sd,)
last=$((1400 + (last - 1400) * k))
kr=1; [ "$modo" = 2 ] && kr=2  # (mode 1: the scenes keep one update per present)
rel=$(for t in $(seq 30 30 600); do echo -n "$((t * kr)),"; done)
out="build/teste60/$cena-$modo"
rm -rf "$out"; mkdir -p "$out"
fps=()
[ "$modo" = 0 ] || fps=("LARECOMP_FPS60=$modo")
tools/repro.sh "t60-$cena-$modo" "$last" "LARECOMP_INPUT=$route" "LARECOMP_SHOT_REL=${rel%,}" "${fps[@]}" "$@" >/dev/null 2>&1 || true
cp "build/repro/t60-$cena-$modo"/{rel,mid,fin}_*.png "$out/" 2>/dev/null || true
n=$(ls "$out"/rel_*.png 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && FFMPEG=ffmpeg ./.venv/Scripts/python tools/contact_sheet.py "$out/sheet.png" $(ls "$out"/rel_*.png | sort -V) >/dev/null
echo "$out: $n images (the scene started at frame $(grep -o 'scene start [0-9]*' "logs/repro-t60-$cena-$modo.log" | head -1 | grep -o '[0-9]*$' || echo '?'))"
