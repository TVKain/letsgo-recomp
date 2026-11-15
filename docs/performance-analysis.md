# Performance analysis

_2026-10-17. The measurements below tell apart earlier logs, a new deterministic test and work not yet measured. No
number in this audit is attributed to a particular GPU._

> **Review of 10/17 (later validation):** this audit's test ini (`build/audit-dynamic.ini`) was written with CRLF, and
> the `larecomp.ini` reader only stripped the CR from `mod` and `game_lang`: `resolution = dynamic` became "Automatic",
> and the in-game runs described below **did not have dynamic resolution on** (the old code does not log `[dynres]`
> that way either, not even forced to 20 fps). Redone with an LF ini, same Eevee 1.0.0 route at 30 fps: old code
> 1.00 → 0.60; new code between 0.95 and 1.00 (it only reacts to the loading stalls); 60 mode in the world at 60.49 fps
> on average. The reader now strips CR/LF from every line (HISTORY 56). Revised priority: **P3**, because dynamic
> resolution is not in the launcher (only `resolution = dynamic` edited by hand).

## Available baseline

The renderer logs windows of about 2 s in `runtime/nvn/vulkan/device.c`: the window's fps, the longest gap, draws,
passes, uploads and compile time. `tools/perf_summary.py` summarizes them. In this audit, from **pre-existing** logs
(the sessions were not repeated, so they are not comparable as a benchmark):

| Log | Length | Mean fps of the windows after boot | Windows with a frame >50 ms | Draws skipped | Programs compiled |
|---|---:|---:|---:|---:|---:|
| `logs/repro-menu.log` | 52 s | 31.4 | 4/25 | 716 | 473 |
| `logs/repro-link2.log` | 96 s | 30.7 | 6/47 | 514 | 444 |

A new run, `build/audit-dynamic-world.log` (Eevee 1.0.0, copied save, 30 fps, dynamic resolution, 1280×720 window,
audio off), reached the world at present 1450: 48 s, 23 windows of ~2 s at 30.0 fps, one window with a 64 ms longest
frame, 527 draws skipped in 7 compile windows, 479 programs compiled. There is no `[dynres]` line, so no scale
reduction was logged. The capture `build/window.png` showed the 3D scene. **Audio was not tested** in that run.

These sessions involve different scenes, compilation and options; the numbers do **not** measure the fix's gain. The
parser gives the mean of the windows, not a frame-weighted mean fps. Nor does each window's longest gap allow
rebuilding percentiles.

Optional per-present collection was added in `runtime/nvn/vulkan/device.c` (`LARECOMP_FRAMETIME_CSV=<path>`),
summarized by `tools/frametime_summary.py` with nearest-rank percentiles. In a new Eevee run,
`build/audit-30-frametimes.csv`, filtering the world's presents 1320–1449: **130 samples, mean 33.332 ms (30.00 fps),
P95 34.326 ms, P99 43.453 ms, max 58.980 ms, one frame >50 ms**. These are intervals between **the game's presents**,
not GPU work times. CPU/GPU, RAM and VRAM remain unmeasured.

In the range 1360–1449, after entering the world in both modes, with the same copied save and scripted input:

| Mode | Samples | Mean | P95 | P99 | Max | >50 ms |
|---|---:|---:|---:|---:|---:|---:|
| 30 fps | 90 | 33.334 ms (30.00 fps) | 33.723 ms | 34.966 ms | 34.966 ms | 0 |
| experimental 60 | 90 | 16.540 ms (60.46 fps) | 18.152 ms | 18.585 ms | 18.585 ms | 0 |

The 60 mode's log marked `world: 60 fps` at present 1342. The scenes may be at different game times despite having
the same number of presents; the table compares **cadence**, not gameplay quality or GPU gain. Neither run had a
`[dynres]` line. Audio was off in the tests.

## Bottlenecks and costs found in the code

- **Initial shader/pipeline compilation:** `runtime/nvn/vulkan/exec.c` uses workers and a per-draw wait budget;
  `renderer_stats()` exposes translation, SPIR-V, pipelines and draws waited. The earlier research in
  `docs/HISTORY.md`, part 8, measured pop-in and the cache's effect. Repeat with a cold/warm cache and on both target
  GPUs before changing the budget.
- **Submission and synchronization:** `LARECOMP_VK_PROF=1` separates execution time, descriptor sets, vertex copies and
  submit; the `[hitch]` log flags frames over 50 ms. There are no new samples of these counters in this audit.
- **Dynamic resolution:** it decided wrongly at 30 Hz, lowering the resolution with no real performance pressure. The
  change is a **quality and control fix**, not an FPS optimization.
- **Dispatch and recompilation:** `runtime/dispatch.c` uses a direct per-thread cache for indirect calls;
  `runtime/cpu.h` adds a profiler/hook branch at every entry. There is a potential cost, but it was not profiled, so
  there is no case for replacing it with LTO/PGO or speculative parallelism.

## Reproducible comparison of the fix

`tools/test_output_scale.c` calls the real `output_scale` implementation over 180 synthetic presents. Building it
against `git show HEAD:runtime/nvn/output_scale.c` and against the changed file isolates the decision logic:

| Scenario | Before | After | Criterion |
|---|---:|---:|---|
| 30 mode, 33.33 ms per present | scale 0.70, test fails | scale 1.00, test passes | Do not lower the resolution at the nominal rate. |
| 30 mode, 45 ms per present | — | scale 0.70 | Still react to persistent load. |
| 60 mode, 16.67 ms per present | — | scale 1.00 | Keep the nominal 60 Hz behaviour. |
| 60 mode, 25 ms per present | — | scale 0.70 | Lower the scale when 60 Hz is not held. |
| Transition 30→60→30, 90 presents in each nominal phase | — | scale 1.00 | Do not mix samples of different rates. |

Test command: `clang -O2 -Iruntime tools/test_output_scale.c runtime/nvn/output_scale.c -o build/test_output_scale.exe`,
then `build/test_output_scale.exe <30|60> <ms>` for the four values and `build/test_output_scale.exe transition`. The
final 0.70 scale depends on the 180 frames and the current cooldown; the test checks the direction of the decision.

## Next profiling round

1. Repeat the `LARECOMP_FRAMETIME_CSV` collection over the same stretch of world, save, input, resolution and cache,
   separating boot/loading; quantify the CSV's overhead in a paired session.
2. In 30 and 60 sessions, log `LARECOMP_VK_PROF`, `LARECOMP_FNPROF`, the renderer stats, CPU per thread, RAM/VRAM use
   and GPU timestamps. Capture RenderDoc/Nsight only on the slow frames; continuous capture changes the pacing.
3. Compare a cold/warm cache, SMAA on/off and 1080p/1440p/4K. Only then choose between optimizing shaders, descriptor
   sets, uploads, submits or synchronization.
4. Run the same scenario on Eevee and Pikachu; keep results from different machines apart.

There is no before/after FPS comparison of the fix because no paired game benchmark was run. The isolated test proves
the **scale decision**; the new run checks that the game started and showed the world with no scale reduction logged,
but it does not measure a GPU time gain.
