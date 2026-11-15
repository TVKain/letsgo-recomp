# Progress

The port's current state. The full history, with every problem and how it was solved, is in
[HISTORY.md](HISTORY.md). The diagnostic tools are in [DEBUGGING.md](DEBUGGING.md). The prioritized backlog for a
mature version is in [ROADMAP.md](ROADMAP.md).

_Updated 2026-10-17._

## What works
| Area | State |
|---|---|
| Boot | complete: 4 modules, SDK, constructors, threads, system services |
| Games | *Let's Go, Eevee!* and, since 0.2.1, *Pikachu!* (program id in `main.npdm`), any version. Parity: every feature applies to both (CLAUDE.md); the fixed addresses (60 fps, wild battles, generator patches) have a per-build table for 1.0.0 of both and Eevee 1.0.2 (`runtime/fnhook.c`, `tools/patches.py`, mapped with `tools/addrmap.py`); the other updates (Pikachu 1.0.2, 1.0.1) run without those options. Pikachu 1.0.0 tested: setup, new game up to the name, world, menus, 60 fps, wild battle and capture (save copied from Eevee), PT-BR translation, GO Park. Missing: Pikachu's new game beyond the name, Play with Pikachu, exclusive Pokémon |
| Controller | the PC gamepad as handheld mode (controller selection accepted) |
| Translations / mods | a `mods/<name>/` folder in Atmosphere's format (LayeredFS): romfs files replaced or added, chosen in the launcher ("Translation"). Tested with the fans' PT-BR translation (Pokémon Switch Brasil, v3.1): texts, menus and images in Portuguese. To install: the launcher's "Install translation..." button with the downloaded file (.zip/.rar/.7z), or copy Eevee's `romfs` to `mods/<name>/romfs` |
| Release | `LetsGoRecomp.exe` in a zip (`make dist`): the player chooses the game folder in the launcher, which checks for v1.0.0, copies the files and recompiles the game's code on their PC (frozen generator + Zig); launcher in English or Portuguese |
| Touch screen (Play with your partner) | mouse: the held left button is the finger; controller: the right stick moves a finger (a circle on screen) and holding ZR touches. Petting, opening the berry tray and carrying the berry to the mouth work (tested only with a controller: Eevee ate). Works at any window size and aspect |
| Keyboard and mouse | WASD walks / aims, Space or Enter = A, Q or Backspace = B, Tab = X (menu), R = Y, Z / C = L / R, `=` / `-` = Plus / Minus, arrows = d-pad. Mouse: while aiming the Poké Ball (after "Get ready") it is captured by the window: movement = aim (virtual gyro), left = throw; elsewhere it is free and the left button is a finger on the touch screen (Play with Eevee: petting); right = B always. Keys and mouse sensitivity are changed in the launcher ("Controls" page) |
| Opening video | correct image and audio, 1080p, it ends and moves on to the game |
| Audio | music and effects (Opus via `hwopus`), the videos' audio without gaps |
| Pacing | locked 30 fps (the game's) by default; experimental 60 fps option in the world (item 5) |
| Introduction | language, Professor Oak, character choice, name typed correctly |
| 3D | correct scenery (bedroom, Pallet Town, sky), depth/shadow passes |
| Characters and Pokémon | correct skinned models, animated (the `LDC.64` fix in the shader translator) |
| Gameplay | walking, meeting the Professor, catching Pikachu (centred aim) |
| Save | saving and loading work (`save/save_0/savedata.bin`) |
| Wild battles (experimental, launcher option, off by default; `wild_battle = 1`) | touching a wild Pokémon opens a classic battle against it (real species, level, gender, IVs and level-up moves) and, afterwards, the capture; the world comes back with a fade in. Since 2026-10-23, the 5th CATCH button (native, 9 languages): catch at any time, a better chance with the wild one weak or with a status, one ball at a time (escaped → the battle returns with the same HP), fainted = lost, but the team gains the native XP (and evolves after the battle); no 5-minute clock; also with the starter walking on its own; the defeated wild Pokémon faints; the battle music carries on through the capture and the return (2026-10-24); "Back to battle" in the capture and the return without the opening or a throw; tested by script on Eevee and Pikachu. Missing: the capture's opening, nature/shiny, the ~12 s wait when leaving the battle, and more areas (HISTORY, [BATTLE-MODE.md](BATTLE-MODE.md), step 6) |

## What is missing
1. **Validate the 3D in more scenes** (battles, large Pokémon, cities): the skinned-model fix was validated in Pallet
   Town. History in [HISTORY.md, part 6](HISTORY.md).
2. **Motion aiming**: the mouse (virtual gyro) and the controller's real gyro (SDL, written on 2026-10-16 and kept out
   of `main` in the `git stash` "giroscopio do controle"; **not tested with a real controller**: axis directions to be
   confirmed; `LARECOMP_GYRO_PAD_FLIP=1|2|3` flips yaw/pitch). Sensitivities in the launcher. Missing: pitch drift
   correction from the accelerometer.
3. **Online features** (Pokémon GO, trades, Poké Ball Plus): off on purpose (offline services).
4. **Performance** (measured 2026-10-15, `tools/perf_summary.py` over 4 min walking Route 1): a steady 30 fps (minimum
   28.6 per 2 s window, no frame over 50 ms apart from the test's screenshot, no audio underrun) on an RTX 3080. On
   entering an area, ~0.3 s of objects appearing while the new shaders get ready (with the cache: ~200 ms of
   translation and ~90 ms of SPIR-V for ~380 programs); the first time without a cache, a few seconds. The pipeline
   cache is now saved during play, not only on exit. In gameplay a draw waits for its shader (up to 20 ms per frame)
   instead of vanishing: zero draws skipped after loading. Shader translation runs in parallel: even on the first visit
   (empty cache) the area appears complete after loading. Quality: SMAA on, 16x anisotropic filtering and supersampling
   scaled down well (1440p / 4K in the launcher on a smaller screen; 4K runs at ~78 fps uncapped on an RTX 3080).
   Details in [HISTORY.md, part 8](HISTORY.md).
   Audit of 10/17: dynamic resolution treated a steady 30 fps as 60 Hz slowness; the budget was fixed to 30/60
   depending on the scene. The isolated test and scripted Eevee at 30/60 (redone with an LF ini: before it dropped to
   0.60, now it stays at 0.95-1.00) passed; the option only exists in the ini (`resolution = dynamic`); optional
   frame-time collection gives the mean and P95/P99 ([performance-analysis.md](performance-analysis.md)). Pikachu,
   transitions and CPU/GPU profiling are still missing.
   Profile of 10/17-18 (Eevee, RTX 3080, Route 1 world): uncapped, the world ran at ~60 fps (the ~160 fps note above
   did not repeat on this route); two causes found and fixed: waiting on a mutex in the emulated kernel (HISTORY 57:
   paced 60 fps went from 58.8-59.3 to 60.0 fps) and the GPU reading vertices over PCIe (HISTORY 58: GPU from ~10 to
   ~1.2 ms per frame, uncapped fps ~75 -> ~90). The limit is now the CPU chain between the game's 3 threads
   ([RESEARCH-GPU.md](RESEARCH-GPU.md)). No test on a weaker GPU or an integrated one.
5. **60 fps (experimental, the launcher's "60 fps (experimental)" option, off by default; `fps = 60` in larecomp.ini
   or `LARECOMP_FPS60=1`)**: the world at native 60, menus and Pokédex at 30 with an in-between frame, battles and
   captures at 30 (HISTORY 43-49). History of the investigation: the game's logic moves one step per frame. With
   `LARECOMP_FPS=60` it reaches the same state at the same frame number in half the time, i.e. it runs at double speed
   (measured 2026-10-15 with `tools/repro.sh`). 60 fps would require changing the game's own time step. What is known:
   - The engine chooses the present interval at the end of the frame (`0x7000029e80`, function `0x7000029d30`):
     `clamp(config[+8] / (G − 1), 1, 5)`, with `G` = 16,666,667 ns (one 60 Hz vsync, pointer at `0x70015fb438`). The
     result is 2 and is applied only once (`SetPresentInterval 2`, via `0x70005e79c0`); even paced at 60, the game
     does not ask for interval 1, so `config[+8]` is fixed (~33.3 ms), not a measurement.
   - The only value near 33.3 ms found in `main`'s data and the heap (`33,412,440` at `0x727eeccb68`) is not it:
     replacing it with 16,666,667 changes nothing.
   - The float 1/30 appears once (`0x7000f47428`), used only in an interpolation function (`0x7000611440`), not in the
     loop.
   - The application loop (`0x70000231a0`) calls the update (`0x700001d1c0`) and then the end of the frame through a
     vtable.
   - ~~There is no global time step~~ (**corrected 2026-10-16**: the scan looked for floats and found nothing because
     the step is an integer in nanoseconds, on a stack). There is a time reference: the duration table `G`
     (`main+0xf7eeb8`: 16.7 / 33.3 / 50 / 66.7 / 83.3 ms, pointer at `0x70015fb438`) and a timers object on the main
     thread's stack with two steps. Step 1 is rewritten on every world update by the accessor `f_7000039600` with
     `G[1]`; step 0 stays at 33.3 ms. The systems that use the step's **value** (animations
     `f_7000663660`/`f_7000664cd0`, `f_700067be50`, `f_70005ed1e8`/`f_70005ed908` and others) read step 1 and convert
     time to frames by dividing by `G[1]`; that is why changing `G[1]` in the accessor keeps the world right at 60.
     What does not go through it: integer frame counters (the capture's and battle's timelines) and step 0, which only
     decides whether an object updates. Details and measurements: [RESEARCH-60FPS.md](RESEARCH-60FPS.md), "Time map".
   - Conclusion: 60 fps at the right speed does not come from one patch. The ways would be generating in-between
     frames (interpolation in the runtime, without the game's motion vectors: artifacts, especially in the interface)
     or an external frame-generation program. Research on the techniques other ports use:
     [RESEARCH-60FPS.md](RESEARCH-60FPS.md).
   - **Interpolation prototype removed** (2026-10-15): replaying each frame with blended uniforms worked for the
     camera, but without the game's own markings (as RT64 has) it left visible errors - repeated objects swapped
     (ghosts), blank menus, stretched models, flashes on effects. The game stays at the original 30 fps.
6. **The special Pokémon's aura blinks** (also in the release, at 30 fps): in the player's video (2026-10-17) the aura
   vanishes for exactly 1 game frame, at irregular intervals, with the Pokémon in place. Ruled out by measurement: GPU
   timestamps (`LARECOMP_VK_COUNTER`), sync waits, texture copies to memory, interpolation, and a system clock pinned
   per frame (tested in game by the player: the same). Tools to continue: `LARECOMP_COUNT_TEX=1024x256` and
   `LARECOMP_COUNT_FS=<hash>` (draws per frame), `LARECOMP_TRACE_COUNT` (lists that contain a draw and who calls them),
   `LARECOMP_CALLCOUNT`, `tools/blink_scan.py`. The test route has no Pokémon with an aura; F9 recording changes the
   result itself (the first recorded frame loses the effects), so it serves for structure, not for finding the blink.

## Fixes in the runtime (summary)
| Area | Fix | File |
|---|---|---|
| Kernel | exception context (`svcGetInfo` 20), Title ID from `main.npdm` | `runtime/kernel.c`, `main.c` |
| Kernel | the condvar does not reacquire the mutex on timeout; does not overwrite a "woken" with a timeout | `runtime/kernel.c` |
| Loader | 4 modules (`main`, `sdk`, `subsdk0` glslc, `subsdk1` multimedia) | `runtime/loader.c`, `dispatch.c`, `gamelib.*` |
| Services | offline Bluetooth (`btm:u`, `bt`), `csrng`, `hwopus` | `runtime/services/offline.c`, `hwopus.c` |
| Video | the game's buffers in `GetOutputBuffer`, rotating slots, `FindInt64`/`SetCoreMask`, end of stream `0x2000`, the game's allocator | `runtime/hle/movie.c` |
| `vi` | `SetLayerScalingMode` | `runtime/hle/vi.c` |
| Controller | handheld mode, the styles the game supports, keyboard / mouse, virtual gyro moved by the mouse | `runtime/hle/input.c`, `runtime/hle/bindings.c`, `services/hid_set.c` |
| Keyboard | name in UTF-16 | `runtime/hle/swkbd.c` |
| NVN | per-stage programs, vertex-only programs, pacing by the present interval | `runtime/nvn/cmdbuf.c`, `objects.c`, `vulkan/exec.c` |
| Shader translator | `LDC.64` whose address register is also a destination (skinned models) | `runtime/nvn/maxwell/translate.c` |
| Textures | `RGB5A1`/`RGBA4` converted to RGBA8 (the Pokémon icons) | `runtime/nvn/vulkan/textures.c` |
| Textures | no scaling for CPU-filled textures; invalidation on host writes | `runtime/nvn/vulkan/textures.c` |
| Audio | minimum queue in `audout` + underrun count | `runtime/services/audio.c` |
