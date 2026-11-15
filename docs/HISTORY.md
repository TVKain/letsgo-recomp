# Project history: what went wrong and how it was solved

This document tells, in order, how the port of **Pokémon Let's Go Eevee** went from nothing to the game being playable
(starting a new game, catching Pikachu, saving and loading). Each problem appears with the **symptom** (what was seen),
the **diagnosis** (how the cause was found), the **cause** and the **fix**, with the files changed.

Period: 2026-10-14 and 15 onwards. Current state and what is pending: [PROGRESS.md](PROGRESS.md). Diagnostic tools:
[DEBUGGING.md](DEBUGGING.md).

---

## Part 1: choosing the path

### The idea
Run the Switch game **natively on the PC**, without an emulator, using **static recompilation**: the game's ARM64 code
is translated to C once, compiled as a Windows program, and a *runtime* replaces the Switch's system (kernel, services,
GPU, audio, controllers).

### Why LASRecomp as the base
- [LASRecomp](https://github.com/peiikai/LASRecomp) (Link's Awakening, Switch, MIT license) had already proven the path
  works on the Switch: an ARM64 → C translator, Horizon's kernel/services and the **NVN** graphics API translated to
  Vulkan.
- The analysis ([LASRECOMP-ANALYSIS.md](LASRECOMP-ANALYSIS.md)) showed the core is generic and what is specific to Zelda
  lives in separable layers (patches by address, randomizer, interface).

### Alternatives considered
| Alternative | Decision | Reason |
|---|---|---|
| Start a recompiler from scratch | no | LASRecomp already solves the generic part |
| HWDER (Hyrule Warriors) | plan B for graphics | recompiles the NVN driver and emulates Maxwell commands; license not declared, study only |
| ssbu-recomp (Smash) | study only | GPL-3, incompatible with copying code into an MIT project |
| mk8-recomp | dropped | depends on suyu running |
| Restructure with CMake (an outside suggestion) | no | LASRecomp's Makefile already works; reorganizing does not bring the goal closer |

### The game files (rules)
- The game comes from the **player's own extracted game files**. Result in `extracted/` (outside git): `exefs/` (code),
  `romfs/` (assets) and `romfs.bin` (the raw RomFS image).
- **Nothing from the game goes into the repository:** game files, keys, generated C code, logs, saves and caches are in
  `.gitignore`. The shader harness (`tools/skintest`) generates code derived from the game only locally.

---

## Part 2: diagnosing the binary

Details in [DIAGNOSTICS.md](DIAGNOSTICS.md). In short:

- 4 modules: `main` (the game), `sdk` (Nintendo's libraries), `subsdk0` (**glslc**, the shader compiler) and
  `subsdk1` (**multimedia**, video). Zelda has only `main` + `sdk`.
- LASRecomp's translator converted **100% of the instructions** of the 4 modules (0 unsupported).
- Title ID confirmed in `main.npdm`: `0100187003A36000`.

---

## Part 3: building the fork

1. **Environment:** MSYS2 UCRT64 (clang, SDL3, FFmpeg, Vulkan, shaderc) installed via winget/pacman; Python with
   capstone/unicorn/lz4 in `.venv`.
2. **Removing the Zelda layer:** 16 gameplay/randomizer HLE files and 11 interface screens removed. What the rest of the
   runtime still called became neutral stubs in `runtime/hle/zelda_stubs.c`.
3. **4 modules instead of 2:** the loader, the dispatch table, the game library (`lasgame.dll`, ABI 2) and the Makefile
   now handle `main`, `sdk`, `subsdk0` and `subsdk1` (`runtime/loader.c`, `dispatch.c`, `gamelib.*`,
   `tools/gamelib_entry.c`, `gamebuild.c`, `rt.h`).
4. **The generator without Zelda's patches:** `tools/patches.py` emptied (the patches were addresses in Zelda's
   executable).

First build: the runtime in seconds; the game's code (~550 MB of C) in ~22 minutes.

---

## Part 4: from boot to the title screen

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 1 | Crash in `main`'s constructors (access to `0x1c0`) | disassembly: `nn::os::SetDyingMessageRegion` writes to `[GetInfo(20)] + 0x1c0` | `svcGetInfo` id 20 (the user exception context) returned 0 | allocates an area and returns its address | `runtime/kernel.c` |
| 2 | — (found along the way) | `svcGetInfo`'s code | Zelda's Title ID fixed in the kernel | read from `main.npdm`'s ACI0 | `runtime/main.c`, `kernel.c` |
| 3 | Crash in `nn::vi::GetService` | addr2sym on the backtrace | `nn::vi::SetLayerScalingMode` without HLE (Zelda does not use it) | HLE of the function | `runtime/hle/vi.c` |
| 4 | The game aborts (`svcBreak`) | named backtrace: `nn::btm::user::InitializeBtmUserInterface` | the `btm:u`/`bt` services were generic stubs without objects/events | "offline" services (Bluetooth with no devices) + `csrng` with random numbers | `runtime/services/offline.c` |
| 5 | The game stuck, no frame | a new thread dump (`LARECOMP_THREAD_DUMP`) | a mutex deadlock: on a condvar timeout the kernel reacquired the mutex, and the SDK (`TimedWait` → `Enter` at `0xea01`) did too | the kernel does not reacquire on timeout | `runtime/kernel.c` |
| 6 | Crash in `nvnCommandBufferBindProgram` | the runtime's symbol via `nm` | the game binds a NULL program at the start | (later replaced by item 22) | `runtime/nvn/cmdbuf.c` |
| 7 | "Press a button on the controller you want to use" without accepting the controller | a frame capture (`LARECOMP_SHOT_AT`) + `SetSupportedNpadStyleSet 0x5a` | the runtime presented a **Pro Controller**, which Let's Go does not accept | the controller as **handheld mode** (configurable with `LARECOMP_NPAD`) | `runtime/hle/input.c`, `services/hid_set.c` |
| 8 | Crash on opening the title video | backtrace: `movie::MediaData::FindInt64` | 2 of the 28 video functions without HLE (already foreseen in the diagnosis) | `FindInt64` and `SetCoreMask` | `runtime/hle/movie.c` |
| 9 | ~240 fps, choppy audio | the renderer's statistics | the runtime ignored the game's *present interval* | waits for the game's interval (2 = **30 fps**), `LARECOMP_FPS` to change it | `runtime/nvn/objects.c` |

### The title video (the longest path)
| # | Symptom | Diagnosis | Cause | Fix |
|---|---|---|---|---|
| 10 | GPU "device lost" (a write to address 0) | the Vulkan validation layer | the video textures were shrunk by the **internal resolution scale** and the full-size copy overflowed | CPU-filled textures stay at full size (`vk_tex_unscale`) |
| 11 | Green screen (NV12 with Y=UV=0) | tests by elimination: no scaling, buffers in the game's heap, filling with grey → still green | — (hypotheses ruled out, but they became improvements: `backend_pool_written`, the game's allocator) | see item 12 |
| 12 | Green screen | a log of who reads the frames: the game never called `Buffer::Base` on the video; `GetOutputBuffer` received a **buffer of the game's own** (1920×1080×1.5) | the runtime swapped the game's buffer for its own; the game kept reading its own, empty one | the frame is copied into the game's buffer, in compact NV12 |
| 13 | The video's audio "robotic" | a WAV recording of the output + comparison with the original file (70% of samples exact) + the user's listening test | the decoder immediately reused the just-freed output buffer while the game was still copying from it | output slots in rotation |
| 14 | Music and effects silent (the 6-channel output all zeros) | a WAV recording per output | `hwopus` (the Opus decoder) was a stub: the game gave up | the `hwopus` service implemented with FFmpeg's Opus |
| 15 | The video froze at a random frame | thread dump: the video thread waiting for a mutex **of its own** | a race in the kernel: a signal arrived together with the timeout, the kernel handed over the mutex and still answered "timeout" | keeps the result of whoever woke the thread |
| 16 | The game never left the video (white screen at the end) | the decoders' state + a count of the file's packets (3,458) | at the end of the file the extractor returned `1` (a generic error, "try again") | returns `0x2000`, the real "end of stream", found in the game's own library (`NnMediaCommon::AndroidErrorToNnError`) |

Files: `runtime/hle/movie.c`, `runtime/nvn/vulkan/textures.c`, `exec.c`, `runtime/services/hwopus.c`,
`runtime/services/audio.c`, `runtime/kernel.c`.

---

## Part 5: introduction, 3D and gameplay

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 17 | The name "RRS" appeared as "?S" | bytes: `52 52 53` read as UTF-16 = `U+5252` + `S` | the keyboard returned UTF-8; Let's Go reads UTF-16 | the answer in UTF-16LE | `runtime/hle/swkbd.c` |
| 18 | No 3D (a black screen with sound in the bedroom) | a count of skipped draws by reason: all "noobj" | the game binds **separate programs per stage** (vertex in one, fragment in another, NULL to turn off); the runtime swapped the whole program on every bind | a program combined per stage (`bind_program_stages`) | `runtime/nvn/cmdbuf.c`, `vulkan/exec.c` |
| 19 | ~4,000 draws/2 s still skipped | a log of the stages: `0x1` | programs with only a vertex shader (depth/shadow passes) | an empty fragment shader synthesized | `runtime/nvn/vulkan/exec.c` |
| 20 | The Poké Ball's aim went to the sky | — (the user's report) | the motion sensor (`SixAxisSensor`) not implemented: the SDK read garbage | a neutral sensor (still, level, pointing forward) | `runtime/hle/input.c` |

Result: **correct 3D scenery** (bedroom, Pallet Town, sky), catching Pikachu, **save and load working**
(`save/save_0/savedata.bin`).

---

## Part 6: "exploded" characters (solved)

The skinned models (characters, Pokémon) appeared stretched into "spikes" converging on a point. The static scenery was
correct, so the camera and ordinary geometry worked. The full plan and experiments are in [PLAN-3D.md](PLAN-3D.md).

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 21 | Characters and Pokémon in spikes | a RenderDoc capture + the shader run on the CPU with the same data as the GPU: identical outputs, and the output `w` proportional to the **1st** bone's weight | `LDC.64 R4, c[4][R4+0x38]` (loads R4 and R5 with R4 as the address) became `r4 = cb4[r4+56]; r5 = cb4[r4+60]`: the second read used the **already overwritten** R4. The `w` of the 2nd bone's translation (which should be 1.0) came out zero or garbage, and the vertex went near the camera plane | the translator copies the address register to a temporary when it is also a destination | `runtime/nvn/maxwell/translate.c` |

### The path to the cause
1. **Ruled out with data** (before the plan): attribute format, indices and weights in memory, palette matrices, the
   moment the uniforms are copied, copying the vertices.
2. **Phases 0 and 1** of the plan: deterministic reproduction with the save (`tools/repro.sh`) and binary cuts on the
   GPU. 100% weight on the 1st bone left the models whole; the 2nd bone was wrong. The conclusion at the time, "the
   value of `a11.y` arrives wrong at the GPU", was **wrong**: the test of the shader on the CPU (X5) had passed by
   coincidence, because the vertex used did not exercise the faulty read.
3. **Phase 3, RenderDoc**: the vertex bytes the GPU reads (including `a11 = [7, 6]` and the weights) were identical to
   memory. Running the translated shader on the CPU with the GPU's **exact** data (vertices and `cb3`/`cb4` exported
   from the capture) reproduced the GPU's output number by number. So the defect was in the translated shader itself.
   The log of `cb4` reads in the harness and reading the GLSL pointed to the two lines above.

Until the fix existed, `jogar.bat` used a stopgap (`LARECOMP_VK_SKIN_ONEBONE=1`, 100% weight on the 1st bone: whole
models, stiffer animation).

---

## Part 7: interface

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 22 | Pokémon icons "chopped up" (party, the experience screen after a capture, Pokédex) | a log of the draw's textures (`68x56`, format `0x3B`) and decoding the saved texture with 4 bit layouts: only "R in the low bits, alpha in bit 15" gives the right icon | NVN `RGB5A1` (and `RGBA4`) has red in the low bits; Vulkan `R5G5B5A1_UNORM_PACK16` has red in the high ones and alpha in bit 0: colours swapped and alpha taken from a colour bit | converted to RGBA8 on upload, like RGB8 | `runtime/nvn/vulkan/textures.c` |
| 23 | A blue flash and then black when opening the game | screenshots of the first frames and a log of the clears (`LARECOMP_LOG_CLEARS`, now with the colour): the first 2 presents are a full-screen blue 2D quad drawn by the game itself, with no clear; `nn::oe::FinishStartupLogo` is called already at frame 0, so the system logo would not hide them | not explained (it is not known whether the console shows the same) | the window stays black for the first 2 presents (`LARECOMP_HIDE_FIRST_FRAMES`, 0 turns it off) | `runtime/nvn/vulkan/device.c` |
| 24 | Some objects never appeared (1247 draws skipped as `failed` in 4 min of play) | `tools/perf_summary.py` on a long session's log; the log had `FS translate failed: unknown instruction df5800812ff70400` | the shader translator did not know `TMML` (a query of the mipmap level a sample would use): the whole shader failed and every draw with it was skipped. The game's shader uses the level to limit the sample (`min(lod, 2)`) | `TMML` translated with `textureQueryLod` (8.8 fixed point, components in the reverse order of GLSL, as in Ryujinx) | `runtime/nvn/maxwell/translate.c` |
| 25 | Objects appearing late again the first time in each area after a crash | the date of `cache/vk_pipelines.bin` | the pipeline cache was only written when closing the game normally | written on a background thread ~6 s after a batch of new pipelines finishes (~90 ms, without stalling a frame) | `runtime/nvn/vulkan/exec.c` |


## Part 8: image quality and pop-in (2026-10-15)

An audit of a Route 1 frame (`LARECOMP_DEBUG_FRAME`, images of each pass) and of the Vulkan validation layer: the frame
is a 2048² shadow map → 1080p HDR scene → bloom chain (960x540 down to 10x6) → composition → interface, with no draw
missing. Validation only flags a 16x16 RGBA8 texture (the game's own "no shadow") read by a shadow sampler: outside the
specification, but the NVIDIA GPU compares the red channel like the Switch's Tegra.

| # | What | Measurement | Change | File |
|---|---|---|---|---|
| 26 | Aliasing: the game has no anti-aliasing | window screenshots with and without | the 1x SMAA inherited from LASRecomp (an option in Zelda's Esc menu, removed) comes back on by default, with the "Smooth jagged edges" box in the launcher (a new `smaa` key in the ini: the old `antialias = off` was only the saved default) | `runtime/settings.c`, `runtime/ui/launcher_lg.mm` |
| 27 | Supersampling (1440p / 4K on a smaller screen) scaled down with a single bilinear tap, which skips texels | uncapped, gameplay at ~160 fps at 1080p, ~115 at 1440p and ~78 at 4K (RTX 3080): 4K on a 1080p screen has room to spare for 30 fps | the presentation uses 4 bilinear taps spread over the area of each window pixel (at exactly 2x, the 2x2 average) | `runtime/nvn/vulkan/shaders.c` |
| 28 | Blurry textures at grazing angles (paths, grass in the distance) | the game asks for little or no anisotropic filtering | 16x on samplers with mipmaps and a linear filter (`LARECOMP_ANISO`) | `runtime/nvn/vulkan/textures.c` |
| 29 | Objects appearing a few frames after each batch of new shaders | ~20-60 draws skipped per batch in gameplay; with the cache, ~1 ms per program | the draw waits for the program / pipeline to be ready, up to 20 ms per frame (at 30 fps ~27 ms are spare), instead of being skipped: zero draws skipped in gameplay, the same fps; the ones left fall on the loading screen (`LARECOMP_SHADER_WAIT_MS`) | `runtime/nvn/vulkan/exec.c` |
| 30 | First visit to an area: shaders ready slowly | an empty cache (`cache/` folder moved away): translation ~240 ms on a single thread, while the 16 compile threads waited; after that, what weighs is the driver creating pipelines (~30 ms each) | translation runs on the worker threads (the translator's `RSC2` string buffer became per thread) and compiles right after on the same thread. Even with an empty cache, all the preparation falls in the loading's black frames: the area appears complete (screenshots of the transition) | `runtime/nvn/maxwell/translate.c`, `runtime/nvn/vulkan/exec.c` |
| 31 | The mouse did nothing; the keyboard with Zelda's layout (K/J/L/I) | an encounter found by trial (`LARECOMP_GYRO_TEST`, the game only turns on the sensor after "Get ready") | a keyboard with Let's Go's layout; the mouse captured by the window with a click: buttons = A / B, movement = virtual gyro (later, #34: captured by itself only while aiming; outside it, it is the finger on the touch screen) | `runtime/hle/bindings.c`, `runtime/hle/input.c` |
| 32 | The Poké Ball's aim still in handheld mode | the game read the sensor only 2 times per capture: `IsSixAxisSensorAtRest` always answered "at rest" and the game skips reading a sensor at rest | never "at rest" (a console in the hand never is); coherent orientation, angle, angular velocity and gravity; z axis = horizontal aim, x = vertical. The game measures the turn from the start of aiming and ignores sudden jumps (noise): only continuous movement, like the mouse's, moves the camera | `runtime/hle/input.c` |
| 33 | No way to play translated (the game has no Portuguese) | the runtime already had a full LayeredFS (replacing and adding romfs files) used by Zelda's randomizer seeds, off in Let's Go; the fans' PT-BR translation comes as an Atmosphere folder and replaces the `English` and `Spanish` texts, the interface (`bin/app`) and images | `runtime/mods.c`: the `mods/<name>/` folder chosen in the launcher feeds the same mechanism (without redirecting the saves, as the seed did). The language asked of the system became configurable (`game_lang`), but the game follows the language written in the save: changing only that does not change an existing save's texts | `runtime/mods.c`, `runtime/services/fs.c`, `runtime/ui/launcher_lg.mm` |
| 34 | "Play with Eevee" did not respond | handheld mode pets through the touch screen; the game imports `GetTouchScreenStates<16>` and `GetGestureStates`, neither implemented (it read empty memory) | `GetTouchScreenStates` returns a finger: the free mouse over the game's image (converted to the Switch's 1280x720 screen; the right scale is the TV's, 1920x1080: #36), with Start / End at the beginning and end of the touch; tested petting the forehead: Eevee closes its eyes, musical notes and sparkles. Gestures: the game queries them, but petting does not depend on them (returns none) | `runtime/hle/input.c`, `runtime/nvn/vulkan/device.c` |
| 35 | The real mouse and keyboard interfering with automated tests | the user's mouse position appearing in a test's log | the `input_user_blocked` filter only existed in the Metal backend; Vulkan's event loop did not call it | `runtime/nvn/vulkan/device.c` |
| 36 | The berry button of "Play with Eevee" did not open | touches on the icon in several forms (quick, held, dragged) and the day moved ahead; the disassembly of the game's touch reader (`0x70007c1ac4`) showed it checks the position of each sample, including the release; with the coordinate at 1920x1080 scale the button opened | the runtime tells the game it is on the TV (1920x1080) and the game uses touch at that scale, not the handheld's 1280x720: the icon was at 2/3 of its place. Touches now in pixels of the reported screen (`LARECOMP_DISPLAY_W`), and the release sample repeats the last position (before it went to the default / mouse position) | `runtime/hle/input.c` |
| 37 | Play with Eevee impossible with only a controller | handheld mode depends on the touch screen | a virtual finger: the right stick moves, held ZR touches (ZR does not reach the game, where it only repeats A), a circle drawn by the overlay (`runtime/ui/menu.mm`). The whole flow tested: opening the berries, closing the tutorial with A, taking the Razz Berry, carrying it to the mouth: ×23 → ×22 | `runtime/hle/input.c`, `runtime/ui/menu.mm` |
| 38 | Leftovers of Link's Awakening in the runtime | a survey of each function neutralized in `hle/zelda_stubs.c` and of who called it | the fork had turned off the Zelda layer with stubs, but the calls and the screens were still in the code | removed: the stubs and the calls (warp, pets, doors, golden pots, bottle, hearts, the dungeons' widescreen, the save editor, level change by name), the randomizer, Zelda's texture-based button icon swapper (`texpatch.c`), the old tabs of the Esc menu (the menu now only has the quit question, name typing, the fps and the controller's finger), the old launcher (Mac), building the game's code on the player's machine (`gamebuild.c`, zig) and the Mac Metal backend, which was never built in this project. Zelda's options left `larecomp.ini` (the old ones are ignored) | `runtime/` |
| 39 | Playing required MSYS2, `make gen`, `make` and a `jogar.bat` | a comparison with other native ports (Zelda64Recomp, UnleashedRecomp, LAS Recomp itself): a zip with the exe, the game folder chosen on the first screen, nothing to install | LAS Recomp's release flow (frozen generator, Zig, `gamelib-src/`) had been removed along with the rest of Zelda | `runtime/gamesetup.c` (the folder chosen in the launcher: looks for `exefs` and `romfs` / `romfs.bin`, checks the v1.0.0 build id, copies to `extracted/` and recompiles the game's code with `runtime/gamebuild.c`, the 4 modules); the launcher in English or Portuguese (Windows' language), with progress and explained errors; "Install translation..." (`runtime/mods.c`: opens .zip/.rar/.7z with Windows' `tar` and finds Eevee's romfs); `make dist` (LGPL-only FFmpeg, frozen generator, slim Zig) → `LetsGoRecomp.exe`. A test pitfall: MSYS2's `timeout` does not pass environment variables to native exes |
| 40 | In release 0.1.0, the game closed right after the controller screen (`svcBreak` 2111-0001) | a test of the release downloaded from GitHub in a new folder, without MSYS2: the log showed `[hwopus] FFmpeg has no Opus decoder` just before; the release FFmpeg's `config_components.h`: `CONFIG_OPUS_DECODER 0` | the dependency script inherited from LAS Recomp (`--disable-swresample`) silently turned off the Opus decoder, which depends on swresample; Zelda does not use Opus, Let's Go uses it in all music and effects | swresample on and the script fails if any decoder the game uses is missing (`tools/build_deps_windows.sh`); without Opus the runtime stops with a clear message (`runtime/services/hwopus.c`). Release 0.1.1. Lesson: test the release as a player, until past the controller screen, before publishing |
| 41 | The game build's bar at 100% minutes before the end | a capture of the launcher window during compilation | the generator's progress added 0.5 per module: it closed at 1 with Zelda's 2 modules, but reached 2 with Let's Go's 4 | each module counts 1/4 (`runtime/gamebuild.c`) |
| 42 | In release 0.1.1, a new game (no save) closed on the title screen (`exception c0000005 accessing 0x39`) | a visitor test in two phases (setup through the launcher; then a new game with scripted input): `[movie] cannot open extracted/romfs/bin/movies/EEVEE_GO/title_male.webm` just before | the video player (HLE) opened the videos straight from the `extracted/romfs/` folder, which only exists in the development environment; the release setup creates only the `romfs.bin` image. With a save, the title video does not play, which is why the earlier test passed | the videos are read from inside `romfs.bin` by an FFmpeg reader of our own over `fs.c`'s index (`romfs_image_file`); order: a mod's file, the `romfs/` folder, the image (`runtime/hle/movie.c`, `runtime/services/fs.c`). Release 0.1.2 |
| 43 | The documentation claimed the game has no global time step, and 60 fps in the world worked without explanation | a survey of every read of the `G` table in `main` (`adrp`+`ldr`, 9 instructions), a probe of the step received (`LARECOMP_ELAPSED_LOG`) and a count of who reads each step (`LARECOMP_TIMER_USERS`) | the old scan looked for floats near 1/30; the step is an integer in ns in a timers object on the main thread's stack: step 1 comes from `G[1]` through the accessor `f_7000039600` on every world update, step 0 is fixed. Only the systems that convert time to frames through step 1 follow the clock; frame counters (capture, battle) do not | PROGRESS and RESEARCH-60FPS corrected ("Time map"); mode 2 (divided counters) proved insufficient for the battle (`tools/teste60.sh`): battle and capture keep their logic at 30 |
| 44 | 60 fps (mode 1): in the capture and the battle the in-between frame shook, jumped and blended the interface (overlapping titles, menu panels out of place, white rectangles) | in-between/final pairs saved at the same scene time (`LARECOMP_WINDOW_SHOTS_REL`), diagnosis per buffer and rejection reason (`LARECOMP_INTERP_DIAG`), an invented pixels metric (`tools/interp_metrics.py`) | three causes: (1) the hooks that mark each draw's object were only installed if interpolation was on at boot, and in mode 1 it only turns on inside scenes: everything was paired by order (ghosts, blended interface); (2) interface draws also fall inside objects, so "has an object" did not separate 3D from 2D; (3) the blend was word by word, and a matrix row with one component blended and another kept (crossing zero, or an integer in place of a float) deforms the model; besides, the interval to the final image inherited the world's 16.7 ms at the start of each scene | hooks installed whenever 60 mode is on (`cmdbuf.c`); only draws with an object, a target with depth and the depth test on are blended (the interface keeps the current frame); blending per vec4, all or nothing, accepting 0 as a float; a fixed 33.3 ms period in 60 mode. Measured: battle 42 of 47 frames without invented pixels (the remaining 5 are cuts and large camera moves, coherent in the image), capture 0 of 46 |
| 45 | 60 fps (mode 1): in the battle, stretched characters and deformed Pokémon in the in-between frame (the capture was already good) | scripted battles with in-between/final pairs every 4 frames during attacks (`tools/teste60.sh batalha 1`), the invented pixels metric and enlarged images of the flagged frames | (1) camera cut (Eevee → close-up of the trainer): the trainer's bones far and near were blended (the "jump" threshold accepted changes of up to ~100%); (2) blending per vec4 left part of a bone palette at N and part in the middle; (3) shadows: the shadow map was redrawn with the blended matrices, but the ground (without a game object) used N's light matrix and the shadow slid | before the redraw, each object measures how much its buffers changed: above 20% of the words with a big step it keeps N's pose; if the rejected ones concentrate most of the change (a cut), there is no in-between frame; a jump in any word leaves the whole buffer at N; every 3D draw (a target with depth and the test on) is blended, with or without an object (those without form a group). Measured in two battles: 1 of 201 frames flagged, coherent in the image (a fast camera zoom) |
| 46 | Even with fixes 44 and 45, interpolation in battles and captures stayed bad in the in-game test | the player's assessment at real speed | the automated measurements (invented pixels) did not catch what bothers in motion | interpolation taken out of 60 mode (`exec.c`: only with `LARECOMP_INTERP=1`, research); battles and captures stay at 30 without an in-between frame; the world, menus and Pokédex stay at native 60 |
| 47 | 60 fps (mode 1): menus and Pokédex sped up | the menu opened with `X` at 30 and in mode 1, every frame saved (`LARECOMP_SCREENSHOT_EVERY=1`): the menu's ball appeared in 4 game frames instead of 8 | since the "menus at 60" commit, every frame outside battle/capture went to 60; the menu stops the world and counts its own frames | only the frame in which the world update (`f_70002f8bb0`) ran goes to 60; menus, Pokédex and other screens that stop the world stay at 30 (measured: identical to 30's frame by frame) |
| 48 | After 47, menus and Pokédex no longer sped up, but were locked at 30 (the player remembered a version in which they were perfect at 60) | a comparison with the tested versions: the "perfect" one had the in-between frame on those screens | menus and Pokédex are only smooth and at the right speed with the logic at 30 and the in-between frame; at native 60 they speed up | interpolation on only in menus (`fps60_menu`: world stopped, no battle or capture), a fixed 33.3 ms period; battle and capture stay without it. Measured in the menu opened with `X`: in-between frames without invented pixels |
| 49 | The Pokédex locked at 30 even with the in-between frame in menus; at the opening the counter swung between 30 and 60 | scrolling the list with each in-between/final pair saved; rejection diagnosis (`LARECOMP_INTERP_DIAG`) | (1) the Pokédex is 2D, and 2D was out of the blend; (2) the battle's cut detector rejected every menu frame (almost every screen change is large); (3) with 2D on, recycled rows of the list crossed the screen in the middle; (4) at the opening the in-between frame turned on and off (screens without the world, loadings) | in menus 2D is blended too, without the cut detector, with a strict jump test for 2D (a change above 30%: the draw stays at N); a menu in-between frame only after the world has run the first time. Measured: Pokédex scrolling 25 of 25 frames interpolated without invented pixels; main menu without invented pixels |
| 50 | In the capture's aim, with the stick released, the aim kept moving; any touch already moved it | reading the stick in `runtime/hle/input.c` | SDL's raw value went straight to the game, with no dead zone (a still controller reads a few hundred, and the game treats any value as a push) | a radial dead zone with rescaling (`stick_deadzone`, default 0.15, adjustable in the launcher under "Keyboard and mouse": "Stick dead zone"), also in the tests' simulated drift |
| 51 | 60 fps: an ugly flash when opening the menu while walking (standing still it almost never happened) | the menu opened twice while walking, in-between/final pairs saved on the second opening | with interpolation off (world), the two frames saved the last time it was on stayed marked as valid: the next menu's first in-between frame blended the current scene with the previous menu's | the saved frames are discarded whenever interpolation turns off; measured: the second opening while walking without invented pixels |
| 52 | Issue #1: Let's Go Pikachu 1.0.2 on an AMD with Win10 closed at boot (`c0000005` at `0x38`, font), aborted in the GO Park settings and the launcher refused Pikachu; the patch sent made the setup accept "any version" | reading the patch and the user's log; a search for fixed addresses in the runtime and the generator; a test with the user's own Pikachu 1.0.0 (setup through the launcher, a scripted new game up to the name screen) | (1) Yu Gothic Regular on some Win10 installs breaks the game's font engine; (2) `btm:u` lacked `AcquireBlePairingEvent` (cmd 21); (3) the setup checked Eevee 1.0.0's build id. Accepting another version the patch's way would break 0.2.0: the generator replaces 3 instructions at Eevee 1.0.0 addresses (`tools/patches.py`, always) and the 60 fps, wild battle and object hooks are addresses in that `main` | the setup accepts both games by program id (`main.npdm`); parity (a project rule): Eevee 1.0.0's addresses were found in Pikachu 1.0.0's `main` by comparing instruction by instruction, with the relative fields masked (`tools/addrmap.py`: displacements of -0x30 to +0x10, identical struct offsets, the `G` table and slot `0x15fab08` in the same place); the hooks are still written with Eevee's address and `fnhook` translates by build (`rt_fnhook_set_build`, `rt_addr`); the generator moves the 3 patches (`BUILD_ADDRS`, `tools/patches.py`); other builds (updates) go without them and the launcher disables both options; the real version reported to the game (`game_version`); a wait ignores an empty handle slot; a flat dump; Pikachu's save in `save-pikachu/`; the translation by the title id of the game set up; Yu Gothic Medium and MS Gothic before Regular; cmd 21; the overlay menu in EN/PT/RU; the last host calls in the crash report and `lasrecomp-prev.log`. Release 0.2.1 |
| 53 | With 60 fps and wild battles on (0.2.0, in both games), the wild battle got an in-between frame and looked "ridiculous" (the player saw it on Pikachu; the 0.2.0 test only checked that the battle started) | the player's session log: after `encounter intercepted` no `scene start`; the same in the 0.2.0 test log with Eevee | the wild battle is built by the static battles' process (`wildbattle.c`), which never calls `BATTLE_START`: without `g_special`, the stopped world counted as a menu (`fps60_menu`) and went to interpolation | the wild battles mode tells 60 fps when building the battle (`fps60_scene_begin`); the 60 fps log separates the three states (world / menu with in-between frame / battle and capture). Checked by script on Eevee (touched on Route 1: `battle / capture: 30 fps`) and by playing both games. Lesson: test the options together, not only each one |
| 54 | Issue #1 (the second message, which I only saw after answering the first): local trade, Mystery Gift and online co-op closed the game | the user's v2 patch; `service_lookup` (`runtime/ipc.c`): a service without implementation becomes a stub that answers ok without returning an object | `nifm:u`, `ssl`, `bsd:u` and `ldn:u` did not exist: `CreateGeneralService` / `CreateUserLocalCommunicationService` returned without a session and the game used a null pointer | `runtime/services/network.c`: an offline console (nifm without internet 2110-0300, events already signalled, sockets with ENETDOWN, a scan with 0 networks); the other `btm:u` commands without data. Tested by script in both games: local trade searches and B goes back, Mystery Gift stays at "Connecting..." (the game has no offline way out there), GO Park searches and B goes back. Lesson: read the whole issue before answering. Release 0.2.2 |

What remains on a first visit: an object never seen before (a new Pokémon or effect) in the middle of gameplay may
appear 1-2 frames later, because the driver takes ~30 ms to create the pipeline and the wait per frame is 20 ms. From
the second time on, the cache solves it.

Shadows: at 4K the edges already come out soft (the game filters the shadows); a map larger than 2048² would bring
little and would affect the scale of non-16:9 targets - left out. Physics and logic run the game's own code,
recompiled: the behaviour is the Switch's.

---

## Dynamic resolution audit (2026-10-17)

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 55 | Dynamic resolution could drop even with the default 30 fps stable | `tools/test_output_scale.c` ran the real function for 180 presents at 33.33 ms: scale 0.70 before, 1.00 after; at 45 ms, after, scale 0.70 | `dyn_update` compared the time between presents with fixed 60 Hz thresholds (17.4/14.5 ms), while the default pace is 30 Hz (~33.3 ms) | thresholds proportional to the 30/60 Hz pace, and the sample window is discarded when the pace changes; validated in game afterwards with an LF ini (the audit's was CRLF and did not turn the mode on, see 56): Eevee at 30 fps, old code 1.00 → 0.60, new 0.95-1.00; 60 mode in the world at 60.49 fps. Priority P3: the option only exists in the ini | `runtime/nvn/output_scale.c`, `tools/test_output_scale.c` |
| 56 | Values of a hand-edited `larecomp.ini` with CRLF were silently ignored (`resolution = dynamic`, `upscaler = bilinear`, `75%`...) | while validating the audit: the game received `res_mode 0` with `resolution = dynamic` in the ini (a temporary log in `output_scale`); even forced to 20 fps, no `[dynres]` | `fopen` reads in binary mode, so the CR stayed at the end of the value; only `mod` and `game_lang` were cleaned | every line loses trailing CR/LF/spaces before `sscanf`; the same CRLF ini at 20 fps now lowers the scale (1.00 → 0.70) | `runtime/settings.c` |

---

## Kernel locks (2026-10-17)

| # | Symptom | Diagnosis | Cause | Fix | File |
|---|---|---|---|---|---|
| 57 | The Route 1 world (~600 draws per frame) ran at only ~60 fps uncapped, and paced at 60 fps stayed at 58.8-59.3 fps (P99 ~19.6 ms), with no thread above ~41% CPU (1.09 cores total). The Vulkan backend's cost was small (~3 ms per frame; descriptor sets 0.45 ms) | `LARECOMP_VK_PROF` (backend CPU and GPU per frame), per-thread CPU sampled from outside, `LARECOMP_PROF_SVC`: 3 game threads spent ~750 ms of every 2 s in `ArbitrateLock` (~62 thousand calls each, ~12 µs per call). `LARECOMP_PROF_LOCKS`: a single game mutex accounted for ~126 thousand waits in 2 s (`nn::os::LockMutex` called from `main+0x2e704`; `main` has no symbols, the name `addr2sym` shows there is just the nearest one). Disassembly of the SDK (`InternalCriticalSectionImplByHorizon::Enter` and `Leave`): after the svc, `Enter` rereads the mutex word, checks whether it is the owner and repeats the loop, and `Leave` with waiters only calls `ArbitrateUnlock` | Each wait on a contended mutex slept on a kernel condvar (under the global `g_klock`) and ownership was handed to a sleeping thread: ~12 µs of latency to wake a thread on Windows, about a thousand times per frame per thread | Before sleeping, the thread spins for up to 40 µs on its own wait state (`LARECOMP_LOCK_SPIN_US`; 0 restores the old behaviour; off with fewer than 4 logical processors). Ownership is still handed over by `mutex_release`, so the kernel's semantics did not change. `LARECOMP_PROF_LOCKS=1` lists the contended mutexes every 2 s. Measured (Eevee, RTX 3080, 1280x720 window, same binary, interleaved A/B): cost per wait on the hot mutex 12 → 1.2-1.4 µs; its waits ~130 thousand → 41-51 thousand per 2 s; uncapped world ~60 (59.1 and 61.0) → 73.7 and 65.1 fps; paced 60 fps (Route 1, 2 runs each) 58.8 and 59.3 → 60.0 and 60.0 fps, P99 19.6 → 17.3 ms. Pewter City paced at 60 fps: 60.0 fps in both games, already before. Battery (`tools/bateria.sh`) in both games, 3 routes: 0 crashes, 0 validation errors, 0 unimplemented calls, flicker equivalent with and without the spin. Limits: one machine and one GPU; no AMD/Intel, no 2-core machine (the spin stays off there); a new game tested for 6,400 frames with audio only up to the opening. The world's next bottleneck is the GPU (~9-10 ms per frame at 1280x720) plus the rest of the chain between the game's threads. The old documentation said ~160 fps uncapped in the world; on this route I measured ~60 before and ~65-84 after | `runtime/kernel.c` |
| 58 | With the kernel locks solved (57), the Route 1 world still weighed ~9-10 ms of GPU per frame on an RTX 3080 (84% in a single pass), almost nothing in the clipping | `LARECOMP_GPUPROF_AT` with a timestamp per draw and pipeline statistics (`LARECOMP_GPUPROF_DRAWS`/`_STATS`); single-program experiments (skip, 1x1 scissor, half the instances, return at the start of the shader, only fetch attributes), always alternating in the same run; statistics of the shader compiled by the driver. A group of 4 instanced draws cost ~4.9 ms (a third of the GPU), vertex only (0 fragments); the compiled shader is small (48 registers, no spill) and a shader that only reads the attributes cost the same as the full one; the cost vanished without the fetch. Several hypotheses fell along the way as noise: the GPU varies 10-18 ms between runs of the same code | `guest_direct` bound the game's imported heap (system memory) as the vertex and index buffer, "in place" as on the Switch: the GPU reread over PCIe the 8 instance streams (16 bytes each) for each of the ~71 thousand vertex shader invocations of a draw (~9 MB, ~0.8 ms at ~11 GB/s) | A VRAM ring for vertices and indices on discrete cards: the CPU writes to a staging buffer in system memory and each submission starts by copying what was written (an upload buffer, with a barrier); `LARECOMP_VERTEX_READ=direct\|copy\|auto`. The game uses compute to generate vertex data (16-byte buffers read as streams), so the compute storage buffers (and those of vertex or fragment shaders with `STG`) go into an interval set and those ranges are still read in place; a shader that writes to global memory with no storage buffer bound turns the copies off (a warning in the log). Copy by start address and the whole bound buffer (37.3 -> 16.2 MB per frame); index scanning in AVX2. Measured (Eevee, RTX 3080, interleaved runs): GPU 10.2 -> 1.2 ms (-88%), uncapped fps in the world 75.1 -> 89.6 (median; the CPU pays ~1.8 ms for the copies), paced 60 fps unchanged (60.0 fps, P99 17.3-18.6 ms). Battery in both games, 3 routes, with `auto` mode: 0 crashes, 0 validation errors, 0 unimplemented calls, 0 draws skipped, flicker in the same range; Eevee's world with the Vulkan validation layers on: 0 errors; frames within the noise between runs (PSNR ~33 dB against ~34 dB for the same mode). Limits: one machine and one GPU; integrated card and weak GPU untested (`auto` mode keeps the old behaviour on integrated); image equality is not pixel for pixel (the scene does not repeat). Full research and what was discarded (write watch, flattened shader, stacks in vectors): [RESEARCH-GPU.md](RESEARCH-GPU.md) | `runtime/nvn/vulkan/exec.c`, `maxwell/shader.h`, `maxwell/translate.c` |
| 59 | With the mutex (57) and PCIe (58) solved, the next limit was the CPU chain between the game's 3 threads: the Vulkan backend ran on the game's thread and graphics (lists, presentation, textures) delayed the logic | Interleaved A/B with `tools/perf_ab.py` (turbo runs alternated, ratio with a 95% bootstrap interval) and a fast parallel battery (`tools/bateria.sh` + `tools/bateria_scan.py`, ~100 s for 6 routes) | The backend's work (~3 ms per frame) was on the chain: without it the chain runs at ~159 fps | Render thread (`runtime/nvn/vulkan/renderthread.c`): an ordered queue with fence tickets, a stamp of pages written per list, texture destruction and `backend_represent` through `rt_call`; a `renderer_game_frame` counter (game) separate from `renderer_present_count` (backend). **On by default** (`render_thread = 0` in `larecomp.ini` or `LARECOMP_RENDER_THREAD=0` turns it off; `vertex_read = auto\|copy\|direct` also in the ini). The broken map after captures that appeared with it was from the texture pool (item 60). Measured (RTX 3080, interleaved runs, uncapped): Eevee 126.9 -> 185.5 fps (ratio 1.462, CI 1.40-1.53; frame time P99 13.3 -> 9.9 ms), Pikachu 132.1 -> 191.4 (1.449, CI 1.31-1.54); paced 60 fps unchanged (16.63 ms in both modes). Battery of both games, 3 routes, 3 repetitions per mode: frame differences within the variation between runs of the same mode, flicker in the same range, 0 Vulkan validation errors, 0 unimplemented calls, 0 crashes; closing the window exits normally. Limits: one machine and one GPU; the debugging combination validation layers + thread hangs on exit after `_exit` | `runtime/nvn/vulkan/renderthread.c`, `device.c`, `exec.c`, `textures.c`, `runtime/settings.c` |
| 60 | In 0.3.0 (Eevee, `fps = 60`), after entering and leaving a capture the world could stay broken until changing area: fences, a sign and ferns with flat or dark colour, grey patches on the ground | Variants played by hand with a copy of the save: it broke with the render thread or with the vertex copies, without both it did not appear; intermittent. F5 (textures recheck memory) and F6 (vertices in place) do not fix it; `F9` in the good and broken states: the same vertex counts per shader, only the objects' look changes. So: a wrong texture, not stale data. Reading the texture pool path: `nvnTexturePoolRegisterTexture` stored the object's **host pointer**; with counters in the log (`LARECOMP_POOL_FIX=0`) and the automatic capture loop (`tools/capture_loop.py`), hundreds of slots stayed on finalized textures, and slots of reinitialized textures pointed to another object (16 already at boot); the rebinds happen right after each capture | The game finalizes a texture and initializes it again in the same NVNtexture object (streaming) without registering the slot again. On the console the descriptor stays valid; here the slot stayed on the freed host object and showed whatever `malloc` put in its place: right by luck when the same chunk came back, another texture when not. Any change in the allocation pattern (render thread, vertex copies) changed the luck, which is why each option "caused" the bug | `runtime/nvn/objects.c`: the slot also stores the game's object (`NvnTexEntry.guest`); `nvnTextureFinalize` clears the texture's slots and `nvnTextureInitialize` on the same object gives the new host back to them. The render thread and vertices in VRAM are on by default again. Checked: capture loop with both options on, Eevee and Pikachu, a normal world after each encounter (before/after pairs); fast battery of both games with no crash, no validation error, flicker in the usual range. New tools: `tools/capture_loop.py` (walks in the grass, flees the encounters: B, down three times, A), `LARECOMP_INPUT_LOOP`, `[scene]` marks in the log | `runtime/nvn/objects.c`, `nvn.h`, `runtime/hle/input.c`, `runtime/hle/fps60.c`, `tools/capture_loop.py` |
| 61 | Review of upstream LAS Recomp (2026-10-18): what changed since the copy in `reference/LASRecomp` (81bf718, 10/14) and applies to Let's Go, Windows part | A clone of upstream; development is on the `beta_5` branch (255 commits; `main` has only the randomizer and README). Triage commit by commit; discarded Zelda's (randomizer, mini-bosses, `delegate_null` hooks, the font patch), the ones we already have (condvar on timeout, gmem store in draws, vertices in VRAM, CR/LF in the ini) and the Mac/Linux ones. Tests: a game folder named in Cyrillic and Portuguese (a junction to `extracted/`); committed memory measured from outside (Get-Process) in Pewter City; saving scripted through the X menu → Save | (1) UTF-8 paths read through the system code page: `????-ação/exefs/main` did not open; (2) winpthreads commits the requested stack size: 256 MB per game thread; (3) `IFile`/`IDirectory` never closed the host file; (4) after the crash, the "Visual C++ Runtime" box from `abort()`; (5) controllers SDL does not recognize did not become gamepads | (1) a manifest with UTF-8 `activeCodePage` (bcf999a): the new build opens the Cyrillic folder; (2) `_beginthreadex` with `STACK_SIZE_PARAM_IS_A_RESERVATION` (517a19f): private memory 7.2-7.4 GB → 4.7 GB, same working set; (3) `on_close` closes the descriptor (part of 1c805c2); saving still writes the same as the previous build; (4) `_set_abort_behavior` (bc26a48); (5) `gamecontrollerdb.txt` in the data folder (8f28a0e). Also: the crash report names `f_<address>` before the DLL name (dc30ccc). Fast battery of both games with no crash or error, flicker in the usual range | `runtime/platform/windows.manifest`, `windows.rc`, `windows_threads.h`, `windows.c`, `runtime/kernel.c`, `runtime/services/fs.c`, `runtime/hle/input.c`, `runtime/dispatch.c` |
| 62 | Same review, Vulkan and shader translator part | Reading the diffs against our `exec.c`/`translate.c`; battery before/after with the old executable built separately (new `EXE=` in `tools/bateria.sh`) and frames compared: the rendering is the same, only timing changes (Eevee's menu varies like this between two runs of the same build) | (1) `renderer_fence_seq` counted a reused slot that still had the previous submission's flags: an empty-queue fence waited for a value that would never be signalled; (2) empty colour slots at the end of the pass went as `VK_NULL_HANDLE` (the Intel UHD 630 driver hangs on that); (3) the pipeline key copied the 8 colour formats, including those of earlier passes: duplicate pipelines; (4) IPA multiply assumed the multiplier = w; (5) I2I .SAT, SHF and HSETP2 .H_AND outside the hardware's semantics | (1) 37b7ff6; (2) f4cb039 (an empty slot in the middle goes to the log); (3) 3921201; (4) d1c2d8e; (5) d4c2ff6, but SHF .CC/.X/.HI are still ignored instead of bringing down the program | `runtime/nvn/vulkan/exec.c`, `runtime/nvn/maxwell/translate.c` |
| 63 | Same review, performance part: does what upstream measured on Zelda apply here? | GPU per frame (`LARECOMP_VK_PROF`) on the world route at 2x scale, two runs of each, interleaved; `tools/perf_ab.py` (5 + 5 interleaved runs, in both games) with an `EXE=` variant pointing at the previous exe and DLL; battery and frames compared | (1) the bit-by-bit half → float conversion (~12 operations and two branches per half) ran in every stage; (2) the SDK's libc (memcpy, memcmp, strlen...) recompiled byte by byte and the `fesetround` of the slow floating point path (which also touches the x87) cost ~3% CPU on Zelda | (1) **ported** (50a09ed): fragment and compute use `unpackHalf2x16`, vertex stays exact (`LARECOMP_VK_EXACT_H2F=1` restores the old one). RTX 3080: GPU 4.01-4.06 → 3.70-3.81 ms per frame; the frames only differ in the foliage with wind, like two runs of the same build. (2) **tested and not ported** (67bad06, a2b4aa3): DLLs rebuilt for both games, clean battery, but the A/B gave a ratio of 1.008 [0.989; 1.017] on Eevee and 1.001 [0.987; 1.012] on Pikachu (turbo ~180 fps): no measurable gain on this machine, and changing `GAMELIB_ID` forces every player to recompile the game's code when updating. The right dependency stays in the Makefile (the game's objects recompile when `simd.h`/`simd_fp.h` change). In the final battery, once Pikachu's menu route opened the Bag instead of the Pokédex (script timing with 6 routes in parallel); repeated 3 times, the same as the old build | `runtime/nvn/maxwell/translate.c`, `Makefile`, `tools/perf_ab.py` |
| 64 | In 0.3.1, the launcher saved `larecomp.ini` with lines glued together (`fullscreen = 0fps = 60render_height = 1440smaa = 1mod = ...`): on the next read fps, resolution, SMAA, translation, video audio, fps counter, d-pad and wild battles went back to default | Found while reading `settings.c` for the vibration option; reproduced with the launcher in autoplay saving to a test ini (`LARECOMP_SETTINGS`): the old build wrote the glued lines, the new one did not | Commit 8a2e713 (generated by a script) lost the `\n` of 9 `fprintf`s in `settings_save`: the command channel converts `\n` into a real line break (the same pitfall as in CLAUDE.md) | `\n` back; the reader splits a key glued to the previous value (lowercase letters and `_` right before a second ` = `), so an ini saved by 0.3.1 recovers everything: tested with a broken ini, the launcher rewrote fps 60, 1440, SMAA, translation, d-pad and wild battles | `runtime/settings.c` |
| 65 | Risk of a `c0000005` crash at a valid guest address when two threads touch a not yet committed 64 KB block at the same time (not seen in Let's Go; it appeared in the Sword port, which uses the same runtime, in 11 s of a test) | Reading `lazy_commit`: it only accepted pages in `MEM_RESERVE`. The first thread commits the block; the second, which had already faulted before that, finds `MEM_COMMIT`, the handler returns false and the exception becomes a crash. (The host threads' stacks, only reserved since 290e848, are outside the guest window: they do not pass through here) | A race between simultaneous faults on the same block | A page already `MEM_COMMIT` and `PAGE_READWRITE`: retry the access; pages protected on purpose (`plat_protect`, `LARECOMP_WATCH`) still fault, and execution faults (DEP) do not pass through `lazy_commit` (they do not loop). Battery of both games with no crash or error, flicker in the usual range | `runtime/platform/windows.c` |
| 66 | In 0.3.2 (30 fps), after leaving a capture: black trees and plants with yellow stripes, X-shaped bushes with a sign's texture or a flat light blue colour, the ground without the dirt path, until changing area. The player saw it almost always; the automated scripts, almost never | Detectors in the player's game, with the bug on screen, all at zero: an empty pool slot or one with another texture, pool memory touched from outside, buffer→texture copy only on the GPU, image different from memory, registration per object copied or finalized (item 60 had handled the pool; it was not that). The F9 dump with each texture's slot showed the bushes' ground with a 5-texture fragment shader in place of the 4-texture one, texture 0 inherited from the previous draw: the wrong shader, not the wrong texture | The translated program cache (and the compute one) used only the code's address as the key. After a capture the game loads shaders again at addresses that used to hold others; the renderer returned the old translation (another texture layout, other lighting) | The key includes a hash of the shader's code and constants, computed in `SetShaders` (`content_hash`); probing the program table is limited (64 positions). The log counts the addresses that come to hold another shader (`[shader] ... now holds another shader`): in a capture loop (`LARECOMP_INPUT_LOOP_CATCH=1`), 7 captures on Eevee and 9 on Pikachu, no crash, the counter appears in both right after the captures. New tools: the capture loop that really captures, `--leg` and `EXE=` in `tools/capture_loop.py` | `runtime/nvn/objects.c`, `nvn.h`, `vulkan/exec.c` |

---

## Lessons learned
- **Measure before guessing.** The biggest advances came from instrumentation: thread dumps, the reason for skipped
  draws, recording the audio, a log of who calls each function.
- **LASRecomp is "right for Zelda".** Several bugs were assumptions that held for Zelda and not for Let's Go: text
  format, Pro Controller, per-stage programs, the game's video buffer, the end-of-stream code.
- **The game's own library is the reference.** Reading the disassembly of the SDK and of `subsdk1` (for example
  `TimedWait`, `AndroidErrorToNnError`) gave the exact answer instead of trial and error.
- **Thread races show up as random symptoms.** The video froze at a different frame on each run; the cause was a race
  in the kernel, not the video.
- **A passing test has to exercise the failing case.** The shader on the CPU "proved" the translation was right with
  vertices that did not go through the faulty instruction. Running with the exact data of a broken draw (exported from
  RenderDoc) and comparing with the GPU's output solved it in minutes.
- **Register translation: beware of a destination that is also a source.** Instructions that write several registers
  (`LDC.64`, `.128`) can have the address among the destinations; read the sources before writing.

## Real controller gyro (2026-10-16, not validated on hardware)
An idea taken from ScarletNX's `hid_motion.c` (reimplemented, without copying code): a controller with a sensor
(DualSense, Pro Controller) turns the aim like the mouse. `runtime/hle/input.c` enables `SDL_SENSOR_GYRO` when opening
the controller and integrates each `SDL_EVENT_GAMEPAD_SENSOR_UPDATE` (rad/s × time between samples) into the virtual
gyro's yaw/pitch, only while the game is aiming; a 0.015 rad/s dead zone against the bias at rest, samples with an
interval > 100 ms discarded. Options: `pad_gyro_sens` (launcher) and `LARECOMP_GYRO_PAD_FLIP`. It builds (`input.o`,
`settings.o`); the axis directions are still to be checked.

## "Wild battles" mode (2026-10-17, experimental)
Idea: when touching a wild Pokémon, instead of the Pokémon GO style capture, a classic battle and then the capture, as
the game already does with Snorlax, the legendary birds and Mewtwo. Details and addresses in
[BATTLE-MODE.md](BATTLE-MODE.md); code in `runtime/hle/wildbattle.c`; the "Wild battles (experimental)" option in the
launcher (`wild_battle = 1` in `larecomp.ini`) or `LARECOMP_WILDBATTLE=1`.
- **How it works.** The "static" battles are the class A process (factory `17f0a0`), which reads the record of
  `bin/script_event_data/event_encount.bin` by the hash in `[obj+0x98]`. The hook on the touch trigger (`305ad0`,
  replaced whole: the original function later configures the capture scene's handle, which a battle process does not
  accept) creates that process; the hook in the constructor writes a hash of ours; the hook in the lookup (`2bad00`)
  answers with a copy of Snorlax's record with the species, form, level, gender and IVs of the touched Pokémon (read
  from the configuration constructor's `P` object: level = byte `P+0xf0c`, IVs = `P+0xf18..0xf2c`, gender = `P+0x40c`)
  and the level-up moves from `waza_oboe.gfpak`. After the battle, capturing the same Pokémon is the native flow.
- **Symptom: black screen when returning to the world.** Diagnosis: the world was drawn (large passes) and only the
  final passes came out black; `LARECOMP_DEBUG_FRAME`/`g_debug_frame_request` and the log of fade calls (`11ece0`,
  `11ee50`) showed a type 1 fade out at the end of the capture and **no fade in** until the next capture started on its
  own. Cause: the event's script (`FadeOut_` -> `CallWildBattle` -> `GetWildBattleResult_` -> `FadeIn_`) does the fade
  in; we skip the script. Fix: the hook on `2f78d0` (the world, every frame) repeats, 30 frames after the battle, a
  fade in of the same type as the last fade out.
- **Symptom: the battle started with swapped flags.** `CallWildBattle` writes `a0 = a1 = 0, a2 = 1` and the
  constructor leaves `a0 = a1 = 1, a2 = 0`; we copy the script's values.
- **Symptom: a crash when copying the "real configuration".** Two attempts at laying the Pokémon's configuration
  (0x2b8 bytes) over the battle's brought the game down: the object in `x0` at the trigger is 0xb8 bytes (it is not the
  configuration) and the one the constructor returns still had the species zeroed. Turned off
  (`LARECOMP_WILDBATTLE_USECFG`, default 0); the path that works is reading the fields of `P` and building the record.
- **Lessons.** (1) Look first at what the community (pkNX) and the game itself already say: the names of the script
  natives were in strings in `main`. (2) Scripting the test (`LARECOMP_INPUT`) and saving images every N frames showed
  in minutes what three manual rounds did not. (3) `LARECOMP_HOOK_DUMP` requires the full guest address.
- **Missing:** split XP (half on defeating, half on capturing), the touched Pokémon's nature and shininess, regional
  forms (the move table uses the species index), battles of big/aura Pokémon and tests in more areas.

## 2x text with vertical streaks (2026-10-19, PR #13 by Vancete)
- **Symptom.** With the 2x glyph cache (`runtime/hle/font_hires.c`, on by itself from 1080 lines), the "Continue your
  adventure" menu showed thin light streaks between the letters; with `LARECOMP_FONT_SCALE=1` there was nothing.
- **Diagnosis.** Saturating the fill subtraction (outlined fonts) changed nothing. The streaks were at the cells'
  edges: the cell at Kx was written from `cx*K + 1` to `(cx+cw+2)*K - 1`, leaving the first and last column as they
  were.
- **Cause.** When the game reuses a cell, those columns kept pieces of the glyph that was there before. At 1x the game
  rewrites the whole cell (the empty columns too).
- **Fix.** The cell at Kx covers exactly K times the 1x one (`cl = cx*K`, `cr = (cx+cw+2)*K`). Checked in 1080p
  fullscreen (automatic 2x) on Eevee: no streaks.

## 2x interface with garbage icons on Pikachu (2026-10-19)
- **Symptom.** PR #13's parity test: on Pikachu, with `ui2x = 1`, the X menu's icons came out as noise and the
  partner's icon disappeared; with `ui2x = 0`, normal. On Eevee the same comparison came out right.
- **Diagnosis.** Pikachu with the pack generated on Eevee was normal: the defect was in the pack. The two games'
  interfaces have the same 3081 textures (same keys), but the data of all 3081 differed. Regenerating on Eevee gave an
  identical pack (it is deterministic), and in a test folder linked to Eevee's files too. Regenerating on Pikachu gave
  the right pack, identical to Eevee's. So it was an isolated failure: that time waifu2x finished in 37 s instead of
  ~72 s, exited with code 0 and delivered garbage in every image (1 in 7 generations, RTX 3080).
- **Cause.** The packing (`runtime/ui2x.c`, `pack`) accepted any waifu2x output with the right size.
- **Fix.** Each 2x image, reduced to 1x by a 2x2 average, is compared with waifu2x's input (colour and alpha). Mean
  difference above 16 (0..255): the image is left out. More than 10% left out: no pack is produced, and the start
  screen says the upscaler failed and to try again. Measured: good images up to 7.2; the failure's garbage between 66
  and 188. Three generations in a row with the check: 0 images left out.

## Wild battle broke at the start of the game (2026-10-19, issue #6)
- **Symptom.** With "Wild battles" on, the game closed with `exception c0000005 accessing 0x78` right after "A wild
  ... appeared!", before "Go on, ...!". Reported on Pikachu (Rattata level 3, Route 1); the player said a Gamebanana mod
  did the same.
- **Diagnosis.** The capture loop (`tools/capture_loop.py`, `wild_battle=1`) with a Route 1 save (0:11 of play, only
  the Eevee partner and a Pidgey) reproduced it in both games; with more advanced saves, on the same Route 1, it did
  not. The crash is in `f_7000a9ddb0` (called by the battle sequence command `f_7000aeebb0`): it looks for a component
  of the Pokémon that walks along, does not find it and passes a null pointer on. Handling that null (and the one of
  the setter `f_7000155870(0, 0)` that the code itself calls on this path, and which has compiler traps such as a write
  to `0x130`) only moved the crash to another command (`f_7000adc4c0` -> `f_7000a9a8e0`): the static battle's opening
  was made counting on the companion. The battle object's flags (`a3..a6`) do not change that. Changing the party order
  in the menu (Pidgey in slot 0) made the battle run normally. The names of the script natives (`PokePartyIsPartner`,
  `GetPartnerIndex_` = `f_700019a040`) gave the function that tells the partner's slot, `f_70002462e0(0, &slot)`. In
  the save, the party header is at `+0x5A00` (6 indices and, at `+0x0C`, the partner's) and the Pokémon at
  `+0x5C00 + index x 0x104`; the game's live copy is elsewhere.
- **Cause.** When the partner is in the first slot no Pokémon walks along (at the start of the game this cannot even be
  changed), and the static battle's opening does not handle that case.
- **Fix (guard).** On the touch (`trigger_hook`), if the partner is in slot 0, wild mode does not build the battle and
  the game goes on with its capture. Tested in both games: Route 1 save, 3 encounters in each, all to the capture and
  no crash; with Pidgey in slot 0, the battle still happens. **Missing:** a battle also without a companion (the
  complete fix).

## Wild battle: the starter walking alone (2026-10-19, issue #6, 0.4.2)
- **Two reports after 0.4.1.** The user, with Eevee in front and Bulbasaur walking along, fell into the capture with no
  need: the "with a companion" case had only been tested with Pidgey moved to slot 0, and the runs with their save
  found no encounter (I did not check). Vaskiemaia, with Oddish in front, got a battle, but the game closed when
  switching to Pikachu (a video; a log with the same `f_7000a9ddc0`, Pikachu).
- **The game's vocabulary.** In the script natives, "partner" is the Pokémon that walks with the player and "buddy" is
  the starter (`f_70001760d0`: Pikachu form 8 or Eevee form 1). `f_70002462e0(0, &slot)` (the `GetPartnerIndex_`)
  gives the slot of who walks along, not the starter's. In the save, the party header (`+0x5A00`) has whoever walks
  along in slot 0; the save's blocks are checked with CRC16-ARC (the `FEEB` table at the end: size, id, checksum).
- **The cause.** In a single battle, `f_7000a88780` (opening) and `f_7000a8ced0` (switch) send the starter with
  `ee422.bseq` (the virtual method `f_7000a7e090` asks whether it is the starter); the others go with `ee420.bseq` (Poké
  Ball). `ee422` brings into the battle the field model of whoever walks along; with the starter walking alone, the
  static battle does not have that model and `f_7000a9ddb0` reads a null. That is why it also breaks on the switch.
- **What did not solve it.** The game's static battle scripts (`bin/archive/script_amx.gfpak`, 64-bit AMX in compact
  encoding; native names by the hash `h = h * 0x83 ^ byte`, found in the registrar `f_70006705e0`) put away whoever
  walks along and the ridden starter before `CallWildBattle` (`StartFollowPartnerIntoTheBall_` = `f_7000243bb0`,
  `StartRidePartnerIntoTheBall_` = `f_7000243d90`). Calling that before the battle, with or without a wait, erasing both
  (`f_7000244440`, `f_7000244620`), making it reappear ridden (`f_7000244270`, refuses), another template (Electrode)
  and forcing `ee420` (it has the shoulder starter's branch and breaks in `f_7000adc1f0` -> `f_7000a9bf20`) did not
  solve it.
- **Fix (guard, 0.4.2).** On the touch (`starter_walks_alone`), if whoever walks along is the starter itself (or
  nobody), the encounter goes to the game's capture; with another Pokémon walking along, a battle, and the starter can
  come in. 0.4.1's rule ("starter in slot 0") is gone.
- **Tools.** `LARECOMP_SCAN_LEN` / `LARECOMP_SCAN_NOPTR` in the memory scan (docs/DEBUGGING.md).
  **Lesson:** a case only counts as tested when the log shows its event; test with a copy of the user's save.

## SSAO and GI flickering with the camera moving (2026-10-19, PR #16 by Vancete)

- **Symptom.** With ambient occlusion (SSAO) or indirect light (GI) on, parts of the scene (rocks, bushes, characters)
  gained and lost the effect while the camera moved, as if it turned on and off. Seen by the user in battle and walking
  in the Pewter gym; it existed before the PR.
- **Diagnosis.** In automated runs SSAO ran on every frame, with temporal history kept, and consecutive frames did not
  clash. A dump of the occlusion in battle (`LARECOMP_SSAO_DUMP`) had only the background trees. Counting the opaque
  draws before and after SSAO in each frame: in battle, 30 before and 29-30 after; walking in the Pewter gym, 34 to 68
  before (of about 130), changing from one frame to the next.
- **Cause.** The effect was applied at the first translucent draw after 16 opaque ones. Let's Go draws translucent
  objects in the middle of the opaque ones, so what came after was left without occlusion and indirect light, and the
  boundary moved with the camera (culling and draw order).
- **Fix.** SSAO and GI run when the scene pass ends, with all opaque draws done (`ssao_draw_hook`, exec.c). Pewter:
  118-128 opaque before, none after, in every frame.
- **Second cause (battles and captures).** After the first fix, it still flickered in battle, most visibly in the
  defeated trainer's scene. A build with diagnostics (the user reproduced, the log counted) showed the scene's target
  stable, no draw outside and the history kept, but the frame's camera changing: every few frames, the constants slot
  of the scene's draws (vertex cbuf 5, +64) had a camera at the origin (a view without translation, mirrored, near 16
  and no far: the sky's), in every draw of that frame, and the scene's was in no slot as its own projection. SSAO and
  GI read the depth with that camera in those frames. The shader's constants mask did not help (it does not mark that
  slot even in good frames).
- **Fix.** A camera at the origin is not the scene's (`cam_at_origin`); with no camera in the frame, the previous
  frame's is used if it is up to 8 frames old and still (`ssao_settle_camera`, at the end of the pass). Three battles:
  197 to 554 frames with the camera at the origin, all but 1 to 9 (scene start) covered.
- **Side effect fixed.** Applied at the end of the pass, the effect also caught the fade the game draws over the scene
  on the same target: at the opening (a fade from white), the grass appeared grey through the white. Now it comes in
  before the first draw without a depth test after the opaque ones (a fade, the fullscreen passes), or at the end of the
  pass; the 3D translucent draws in the middle of the scene test depth and do not trigger it. Pewter still has no opaque
  draw after the effect.
- **Not part of this problem.** The horizontal bands in the dark frames of the map change come from the 2x interface
  pack (they go away with `ui2x = 0`, with or without SSAO/GI; they exist since 0.4.0).
- **Tool.** `LARECOMP_SET_AT` applies options in the middle of a session, like F12 (docs/DEBUGGING.md).
- **Still open.** Switching the anti-aliasing to TAA with the game running leaves 1-2 black frames: the scene's shaders
  get jittered variants and the draws are skipped while they compile (it already happened in 0.4.x).

## Launcher opening fullscreen (2026-10-21, tests of PRs #17 and #19)

- **Symptom.** With `fullscreen = 1` in `larecomp.ini` (Pikachu's test folder), the launcher opened taking the whole
  screen, and not in the narrow window, taller than wide, that Eevee showed. A capture of the launcher: 1920x1080
  instead of 762x887.
- **Cause.** The launcher calls `menu_apply_window_requests` every frame (for text input), and that function, on its
  first call, applied `SDL_SetWindowFullscreen(g_settings.fullscreen)`: right after `window_as_launcher` left
  fullscreen and set the launcher's size, it went back to fullscreen. Inherited from the fork, from before `ui_window_init`
  and `window_as_game` applied the option. It already existed in 0.5.0, it did not come from the PRs.
- **Fix.** `menu_apply_window_requests` only applies the fullscreen requested by F11 / Alt+Enter. Pikachu with
  `fullscreen = 1`: the launcher at 762x887, and the game at 1920x1080 after Play (`LARECOMP_LAUNCHER_AUTOPLAY` +
  `LARECOMP_WINDOW_SHOT`).

## Viridian City slow: buffer copies waiting for the GPU (2026-10-22, issue #20)

- **Symptom.** An FPS drop in Viridian City (issue #20, RX 7600 + i5-10400F). Measured here (0.5.0, i5-14600KF + RTX
  3080, 1080p, uncapped, `LARECOMP_VK_PROF`): Viridian ~110-155 fps, the render thread busy 89-93% of the time (~8 ms
  per frame) and the GPU only ~1.5-3 ms. The heaviest scene for the backend's CPU, more than Pewter and the Forest.
- **Diagnosis.** The profile gained the CPU time per command type (`ops:` on the `LARECOMP_VK_PROF` line). Almost a
  third of the thread was command 43, `CopyBufferToBuffer`: 2 per frame, ~1.2 ms each. `LARECOMP_LOG_B2B`: copies of
  112 and 32 bytes (constants), none in memory the GPU writes.
- **Cause.** The copy called `renderer_flush()` before the `memmove`: it submitted the work and waited for the GPU to
  finish everything. That is only needed when the GPU writes the source or destination, or reads the destination
  straight from memory; the draws recorded before had taken copies of the constants and vertices.
- **Fix.** Wait only in those cases: ranges the GPU writes (`gpuw`), the storage buffers of shaders with global memory
  (a new `gpur`, read in place) and vertices read in place (VRAM ring off). After the `memmove`, `guest_copy_flush`
  (as in `UpdateUniformBuffer`). `LARECOMP_VK_COPY_WAIT=1` restores the old behaviour. Viridian, interleaved A/B on the
  same exe (4 + 4 runs per scene): Eevee standing 143 -> 180 fps, walking 146 -> 151, Pikachu walking 122 -> 143 (ratio
  1.175, 95% CI 1.08-1.23); the new one won all 12 pairs. Render thread ~8.3 -> ~5.6 ms per frame. Battery of both
  games, new against old: 0 crashes, flicker in the usual range.
- **Still open.** The same exe varies a lot between runs on this machine (120-175 fps; the 14600KF's efficiency cores,
  not confirmed). The vertex copy (~12-19 MB per frame in Viridian) is the thread's next cost.

## Viridian City: the vertex copies leave the render thread (2026-10-22, issue #20)

- **Diagnosis.** After the fix above, the largest share of the render thread in Viridian was the vertex and index
  copies into the VRAM ring: ~12 MB and ~1.1 ms per frame (~10.6 GB/s); the index scan, ~0.05 ms.
  `LARECOMP_VCOPY_SAME`: 85% of the copied bytes equal to the previous copy, but checking with a hash cost as much as
  copying; reusing between frames would need Windows' write tracking on the game's reservation (left for later).
- **Fix.** The render thread reserves the space in the ring and records the draw; two helper threads do the copies of
  32 KB or more (in 256 KB pieces; the render thread helps when it waits). Everything finishes before the submission
  that reads the copies and before the thread itself writes to the game's memory in the middle of the list
  (`UpdateUniformBuffer`, buffer copy, texture-to-buffer copy, counters). The game only rewrites vertices after the
  frame's fence, which comes after the submission. `LARECOMP_VK_ASYNC_COPY=0` restores the old behaviour.
- **Measured.** Viridian, render thread CPU ~5.6 -> ~3.6 ms per frame (the helpers finish before the submission: 0 ms
  of waiting). Interleaved A/B, same exe, 4 + 4 runs: Eevee standing 188 -> 196 fps (ratio 1.044, 95% CI 1.027-1.057),
  walking 172 -> 181 (1.054; 1.037-1.063), Pikachu walking 171 -> 181 (1.061; 1.020-1.070); the new one won all 12
  pairs, lower p99. The render thread stopped being the bottleneck in Viridian: the rest belongs to the game's threads.
  Battery of both games, 2 repetitions, with and without: 0 crashes, equal flicker.
- **Test note.** In Git Bash, putting `/c/msys64/usr/bin` at the front of `PATH` makes scripts run in MSYS2's bash,
  and exported variables do not arrive (`TAG`, the battery's `REPS`, `LARECOMP_*`): do not change `PATH` before calling
  scripts.

## Viridian City: spinning before sleeping on condition waits - tested and not adopted (2026-10-22, issue #20)

- **Context.** After the two backend fixes, Viridian is limited by the game's three threads: each spends ~45-55% of the
  time waiting for the others in `WaitProcessWideKeyAtomic`; the rest is almost all recompiled game code, with no
  dominant function (sampling the threads' instruction pointer, ~500 Hz; the runtime is ~5%).
- **Measured** (`LARECOMP_PROF_CONDVAR`, new): ~8,000 wakeups every 2 s, mean latency ~8-9 µs (~70 ms in total), almost
  half of the waits under 50 µs.
- **Experiment.** Spin for up to 40 µs on the own wait state before sleeping (like the mutexes, HISTORY 57). The total
  latency fell to ~45 ms, but the interleaved A/B (4 + 4 runs per scene) showed no gain: Eevee standing 202 x 201 fps,
  walking ~187 x ~187, Pikachu walking ~185 x ~183. Removed; the meter stays.
- **Seen in the A/B.** Slow runs (~123-135 fps against ~185-205) appear in both variants, at random: the same exe is
  bimodal on this machine (i5-14600KF, performance and efficiency cores). A hypothesis to test: the game's threads
  landing on efficiency cores.

## Slow runs in the measurements: the window composited by Windows, not the efficiency cores (2026-10-22)

- **Symptom.** In the Viridian measurements (uncapped), the same exe came out bimodal: ~185-205 fps or ~115-140, at
  random.
- **Hypothesis discarded.** The i5-14600KF's efficiency cores: with the process pinned to the performance cores
  (logical 0-11), and even to one logical per performance core, the slow runs went on; on the efficiency cores only,
  94-103 fps.
- **Cause.** The game's window: `nvidia-smi` and the foreground window read every 0.5 s. The same GPU clock (1875 MHz,
  P0) in all of them; fast runs with the window focused and covering the screen (GPU load ~50%), slow with it behind
  others or smaller than the screen (65-77%). Windows composites those windows (DWM) instead of showing them directly:
  1920x1080 focused 182-188 fps, 1280x720 focused 151-158 (a 300 Hz monitor: it is not the screen's ceiling).
- **For players.** With a cap, no measured effect: Viridian at 60 fps with the composited window gave 60.0 fps, p99
  ~17.4 ms.
- **Fix (measurement).** `tools/perf_ab.py` brings the window to the front (always on top, focused) in each run.

## Viridian City: the vertices stay in VRAM from one frame to the next (2026-10-22, issue #20)

- **Diagnosis.** 85% of the vertex bytes copied to VRAM each frame in Viridian were equal to the previous frame's
  (`LARECOMP_VCOPY_SAME`): still meshes, copied again every frame (~12 MB). Checking with a hash cost as much as
  copying.
- **Fix.** The game's heap is reserved separately with `MEM_WRITE_WATCH` (Windows marks the pages written by anyone:
  the game's code, ours, the system's; `plat_written`). A vertex copy is kept in VRAM (two 128 MB areas, staging + VRAM,
  like the ring) and used again while none of its pages has been written after it (an epoch per page, noted at each
  query). What the game rewrites every frame (found written in two queries in a row) goes to the ring as before,
  tested again every 64. When the active area fills, the other one is retired (its copies stop being used) and emptied
  when the GPU has finished reading it, with no wait. The file service rewrites one byte of each page read into the
  game's memory, so that the tracking sees it for sure. A heap that changes size, or a reboot: everything discarded.
  `LARECOMP_VK_KEEP_VERTICES=0` / `LARECOMP_WRITE_WATCH=0` turn it off.
- **Mistakes along the way** (caught in the measurements, fixed before the commit): waiting for the GPU on an area used
  by the frame not yet submitted hung for 10 s (Forest); with both areas read every frame, none became free and the
  cache stopped accepting copies; the volatile ranges counter let them be recopied at every query.
- **Measured.** Vertex upload per frame in Viridian 12.5 -> 2.6 MB (~4 GB every 2 s read from the kept copies).
  Interleaved A/B, same exe, window in the foreground, 4 + 4 runs: Viridian Eevee standing 201 -> 224 fps (ratio 1.110,
  95% CI 1.102-1.124), walking 185 -> 215 (1.162; 1.148-1.169), Pikachu walking 187 -> 215 (1.151; 1.145-1.162);
  Forest +7-10% in the comparable runs (that save's camera varies). The tracking alone, without the cache: no measured
  cost (190.1 x 189.5 fps). Battery of both games with and without the cache, 3 repetitions: `bateria_scan cmp` OK on
  the 6 routes, 0 crashes; `capture_loop` in the Forest: the world comes back the same after the encounters.
- **Limits.** Windows only (Linux has no tracking: it stays off). Importing the heap into Vulkan with the tracked region
  tested only on NVIDIA: in 0.6.0 the tracking (and with it the cache) only turns on by itself when the main display
  adapter is NVIDIA (`EnumDisplayDevices`, before Vulkan exists); on other cards `LARECOMP_WRITE_WATCH=1` turns it on,
  and the log says whether it stayed on. On a card that refuses the import, the log shows "guest heap import failed".

## The Finish of each frame: the render thread made the game slower (2026-10-23)

- **Symptom.** Uncapped and with the GPU idle (effects off, or 4K with only SMAA), the game ran slower with the render
  thread than without it: Pallet Town (Pikachu) 122 fps on against 179 off, 3 + 3 interleaved runs. The opposite of what
  item 59 measured in Pewter.
- **Diagnosis.** Sampling the threads (instruction pointer and return addresses on the stack): no thread saturated
  (render 31-39 %, the game's three 21-31 %), all waiting for each other. Temporary counters in `nvnSyncWait` /
  `nvnQueueFinish`: one `nvnQueueFinish` per frame, ~4.4 ms each (draining the render thread's queue and then waiting for
  the GPU). Always called from the same point of the game's frame loop (Pikachu `main+0x29eec`): `fdiv d0, d0, 1e6` /
  `fmov d1, #4.0` / `fcmp` / `b.pl` - the game only calls Finish when the GPU time it measured in the previous frame
  (the two `ReportCounter`s, in ns) was under 4 ms. The counters measure our translation time, always under 4 ms: Finish
  on every frame, and the game, the render thread and the GPU in series.
- **Fix.** With the render thread, that Finish follows the path the game itself uses when the GPU takes 4 ms or more
  (no Finish; its fences still hold). The point is recognized by the instructions (the return address and the four
  before the call; a unique pattern in `main`), not by address. The other Finish calls (the same loop calls another when
  the video mode changes) do not change. `LARECOMP_FRAME_FINISH=1` restores the old behaviour.
- **In passing.** `CMD_FENCE_SYNC` (a fence recorded in a list) read `x[1]` (the condition, always 0) instead of `x[0]`
  (the sync): those fences were never marked. Fixed; with the render thread the sync receives, when the list is
  submitted, the ticket of the work that runs it (`nvn_list_*`, `objects.c`), and `nvnSyncWait` waits only for that
  work. Let's Go does not use fences in lists (the waits without a fence are from `nvnWindowAcquireTexture`'s sync): no
  effect here. `rt_dispatch` (the game's indirect calls): the slow lookup moved out of the function, which saved 5
  registers and set up the stack on every cache hit; `rt_fnhook` looks at the hook table before the per-thread variable.
  +1.5 % (4 + 4).
- **Measured** (RTX 5070 Ti, 4K fullscreen, no effects: `aa = off`, SSAO / GI / blur / smooth shadows off; uncapped,
  interleaved runs, the same copied save): Pallet Town standing 145 -> 307-313 fps (3 + 3 and 4 + 4), menu open 140 ->
  300, the route to Route 1 147 -> 260, walking in Pallet Town mean frame time 8.5 -> 5.0 ms (P95 8.4 -> 4.7); without
  the render thread 204 -> 211. Capped: 30, 60 and 120 fps and 2x frame generation with the same pace and P95/P99 as the
  previous build. Images within the variation between two runs of the same build (PSNR 29-36 dB against 27-33); a full
  capture of a Pidgey on Route 1 with no defect.
- **Now.** With the render thread ~50-70 % busy, the limit is the game's three threads (recompiled code ~87 % of their
  active time). The heaviest function, `f_7000608b30` (Pikachu), ~13 %: a linear lookup by hash that recomputes the
  FNV-1a of each candidate's name, byte by byte - the game's own algorithm. `rt_fnhook` (every function start, because
  there are always hooks) ~4 % and `rt_dispatch` ~3 %: lowering them requires changing `FN_ENTER` and recompiling the
  game's code. Compiling the game's code with -O2 changes nothing: the player's `zig cc` produces identical objects with
  -O1, -O2 and -O3.

## Wild battles: catching mid-battle, with a native 5th button (2026-10-23)
Request: catch at any moment of the battle, easier with the wild one weak or with a status, one ball at a time (it
escaped → back to the battle), fainted = the chance is lost, and a new, native option in the menu. Research and
addresses in [BATTLE-MODE.md](BATTLE-MODE.md), step 6; code in `runtime/hle/wildbattle.c` and
`runtime/hle/catch_button.c`.
- **The battle engine no longer has the classic throw** (only sequences that send the Pokémon to fight). The capture is
  the GO scene: the battle ends as a flight and the runtime swaps the result (3) for a victory (1), which the post-battle
  process handles by opening the native capture.
- **Symptom: the battle's HP did not reach the capture.** The object that goes to the capture came out with full HP even
  after the wild one fainted. Cause: HP lives in the battle Pokémon (BTL_POKEPARAM, `+0x7e`) and is only given back at
  the end (`9e4280`); the capture uses another object. Fix: keep HP and status at that end and give them back when the
  rematch is built (`9e2490`).
- **Symptom: the read watch did not see the catch rate.** The raw copy of `personal_total.bin` on the heap is read by
  nobody; access is through `71dfd0` (GetPersonalParam, id 8). A hook there.
- **Symptom: with the 5th button, the cursor did not move and FIGHT brought the game down.** Cause: the `uikit`
  navigation grid stores the number of columns (4) in a field that looked like a vector. Fix: 5 columns.
- **Symptom: the 4 buttons came out ~207 to the right of what the layout said.** Cause: the code positions them from the
  right edge of the `B_bounding_00` area (which I had widened). Fix: do not widen the area. (Later, in the user's test,
  the row ended up one step left of the original: with 5 buttons the game already starts one step earlier, and I was
  still shifting the area. Fix: the area stays where it is; CATCH ends where RUN used to end.)
- **Symptom: CATCH animated when chosen, but nothing happened.** Cause: the game only binds to decisions the 4 buttons
  of a fixed table (a callback written into each button). Fix: the runtime writes the same callback into CATCH, with a
  frame-5 view (id 0, ignored by the game), and handles that case.
- **Trainer and 2-player battles** keep the 4 buttons: `fs.c` delivers the built files only during the mode's battles
  and the originals (padded with zeros) in the others. Tested with `LARECOMP_WILDBATTLE_CATCH_MENU=0`.
- **Lessons.** (1) Before changing data, see what the code does with it (positions and ids came from the code). (2)
  Tests in battle need inputs counted from the start of the battle (`b<N>`): the encounter changes frame on every run.
  (3) Swapping the result of a game stage (flight → victory) reused the whole native flow.
- **Symptom (user): the game crashed with the "Traducao PT-BR" mod.** The mod brings the button labels in BC3/BC1 (the
  game uses BC5/BC4); the texture swap refused the format, the language file was left without the button, but the menu
  settings already asked for 5 buttons. Fix: the swap converts to any of BC1/BC3/BC4/BC5 (BC1 with a 1-bit transparent
  background), the build is all-or-nothing (11 files or the game's menu) and the label becomes CAPTURAR in a Portuguese
  mod. **Open:** with that mod the button appears as a black square. The textures reach the GPU correctly (checked
  with `LARECOMP_DUMP_TEX_FMT`) and the mod's layout is the game's; swapping CATCH's textures for the mod's own FIGHT
  ones the button draws right, so the problem is in using BACK's textures in the mod's file (the cause is not known
  yet). Without the mod, right.
- **Symptom (user): a 5-minute "MATCH TIME" clock.** Building the static battle (`28c770`, the same as Snorlax's and
  the legendaries') writes 300 s at `+0x562` of the battle event. Fix: a hook after it, only in our battles, zeroes the
  time (without time the game does not show the clock). Also turning off bit `0x80` of `+0x574` brought the game down
  (see below).
- **Symptom (user): defeating the wild one gave no XP.** The legendaries' rule: with bit `0x80` of `+0x574` (and the
  byte `+0x584`), a knockout ends the battle at once, with no fainting and no XP; the XP check is `9d8ae0` (competitor
  ≤ 1, `+0x4a4` zero, no `0x80`/`0x800` in the setup flags at `+0xe0`). First attempt: turn the bit off. The wild one
  then faints as against a trainer, but that sequence looks for a model that does not exist (`a9c700` reads a null
  pointer: `c0000005` at `651b40`) and, with that worked around, it still waits seconds standing still. Fix adopted: the
  bit stays (no fainting, like the legendaries) and the hook on `9d8ae0` answers "XP on" in our battles: "Bulbasaur got
  10 Exp. Points!", the bar fills and "Your party Pokémon in waiting also got Exp. Points!", then the battle ends.
- **Request: the capture's "Run away" goes back to the battle, with a name that says so.** They are lines from
  `poke_get.dat` (line 24 the button, 4 the question, 14 the confirmation), swapped by the line hook only during our
  capture: "Back to battle", "Do you want to go back to the battle?", "Back to the battle!" (9 languages).
- **Request: going back to the battle without the encounter's whole opening.** The opening is the `ee330.bseq` sequence
  (the camera on the wild one, 160 frames), the line "A wild X appeared!" and the send-out (`ee420`). `fs.c` builds a
  1-frame `ee330` at boot and delivers it only on the return (`wildbattle_quick_intro`); the line becomes "The battle
  continues!". Measured: from the first line to "Go on" 27 frames on the return (~890 in the first battle, in the
  accelerated tests).
- **Test pitfall:** `capture_loop` runs at ~250 fps, so real-time waits (sound, loading) become hundreds of frames;
  "690 frames standing still" were ~3 s. Measure in seconds (the `[vk] t=` log) before calling something slow.
- **Symptom (user): hitting the Pokémon did not change the ring's colour** (Pikachu yellow at full HP and at half HP).
  Cause: in Let's Go's formula (`7de080`) the species' rate goes in raised to 0.54, and I multiplied the rate before
  that, capped at 255: on a Pikachu (190) the maximum gain was 17%. Fix: the HP/status factor (up to ×3, ×2.5 sleep) goes
  on the formula's result, from which the ring and the shakes come. Measured: Pidgey at 5/18 HP, 127.9 → 255.
- **CATCH refused with "You can't escape!"** (a Bellsprout trapped by Wrap): CATCH goes out as a flight, and the client
  checks whether it can flee (`a5c350`). Fix: with CATCH requested, the check answers yes.
- **Request (user): going back to the battle still showed the Poké Ball throw.** `ee420.bseq` (the send-out) also goes
  with 1 frame on the return, until the menu's first choice (a switch afterwards has the normal animation). Compressing
  or advancing its commands made the Pokémon not appear; cut down, it does not close the opening line's window, which
  stayed over the menu - so that line is not opened on the return (`aaf230`, a hook just for it). Result: dark screen →
  flash → menu.
- **Question (user): does whoever reaches the level evolve after the battle?** It did not. The post-battle process
  (`319bc0`) marks in state 0 who levelled up (`+0xd8 + slot`) and, in a trainer battle (type 1), goes to state 1, the
  loop that calls `728300` (the check) and `83cef0` (the evolution event, found through the string
  `evolution_event.cpp`); the static one (type 2) goes straight to the capture or to the end. Fix: after a knockout of
  ours, state 0 → 4 becomes 0 → 1. Seen: Chansey level 100 with 1 HP → Bulbasaur at 19 → "Congratulations! Your
  Bulbasaur evolved into Ivysaur!" and Nidoran ♂ → Nidorino with the Pokédex, then the world; on Pikachu too.
- **My mistake along the way:** I counted three "grew to Lv." as three levels of Bulbasaur; they were three Pokémon of
  the party, one level each (XP goes to the whole party). Check whose each line is before concluding.
- **The black square with the PT-BR mod: it was the mipmaps.** In the mod's file the label textures have 8 mipmap
  levels (the game's, 1); the swap rewrote only level 0 and zeroed the rest, and zeroed BC1 is opaque black. On a 1440p
  screen the game reads level 0 (the button appeared right for the user); in the tests at 480x270, a smaller level
  (black). Fix: all levels, each the 2x2 average of the previous one, with each level's Tegra block height.
- **Request: "Back to battle" without confirmation.** First the runtime pressed A on the question (`input_press_a_at`,
  runtime/hle/input.c); the user saw the question flash ("an automatic confirm"). The real fix: leaving the capture is a
  dialog (`7d2380` creates it in `[scene+0x760]`, a state machine at `+0x10`): state 0 (`7de440`) asks and "Yes" leads
  to state 1 (`7de7d0`, the exit). In our capture the hook on `7de440` only writes the next state (1), without opening
  the question. The automatic A was kept only for the next line, "Back to the battle!". (Pressing A on the capture's
  opening line was discarded: the menu cursor starts wherever it happens to, and A opened the Bag or threw.)
- **Request: going back to the battle without the throw and with the Pokémon on the field.** `ee420` (the send-out)
  cut, compressed, sped up or with only its final part left the player's Pokémon off the field until the first move
  (and the camera on the trainer). The original `ee420` stayed on the return: screen → "Go, X!" with the throw → the
  Pokémon → menu; only the presentation camera (`ee330`) and the line "A wild X appeared!" are cut.
- **Open (user requests):** the opening of the capture scene (the camera and "Now's your chance!": the scene is a
  generic state machine, `7cb780`, with the opening inside state 1); the battle music restarts on the return; the
  "ghost" flashing next to CAPTURAR did not appear in the tests (perhaps the runtime's touch cursor, drawn for 3 s after
  the mouse or the touch stick moves).
- **Request: going back to the battle straight to the menu, without the throw (with Eevee on the shoulder it jumped,
  with bugs).** No edit of the send-out sequence worked (the Pokémon stayed off the field). Solution: the send-out runs
  whole, hidden. On the return, the battle's fade-in is held (the screen stays dark from the capture), frame pacing is
  turned off (`g_present_fast`, runtime/nvn/objects.c) and sound is zeroed (`g_audio_muted`,
  runtime/services/audio.c); when the command menu is built (`ab2730`), everything comes back and the fade-in happens:
  the screen opens with the Pokémon already on the field and the menu (works for the ball and for the shoulder
  partner). Limit: 900 frames. Measured: ~540-630 hidden frames, ~2.5 s of dark screen on an RTX 3080. Also skipping
  the presentation of the hidden frames broke the frame count (discarded).
- **Request: after a ball that bursts, the return starts with the wild one's turn** (the throw was the player's turn).
  A "skip the turn" action (types 7, 5 and 0 in place of FIGHT) left the turn waiting for the move choice. Solution: with
  the screen still dark, the runtime presses A on the menu (`input_press_a_at`) and `decide_hook` swaps the choice for a
  flight (4, a complete action, like CATCH); the server's flee roll (`9f7300`, called by the flight `9f3ed0`) answers
  "did not escape", and the "You couldn't get away!" window (line 83) does not open. The screen clears, the wild one
  attacks ("Bellsprout used Vine Whip!") and the menu comes back. Test: `LARECOMP_WILDBATTLE_THEIRTURN=1` does this on
  every return.
- **Symptom (user): after the ball that burst, the wild one only acted when they chose Fight.** The automatic A was
  pressed once, 2 frames after the menu was built; in their game (60 fps) it landed before the menu accepted and the
  screen cleared through the safety limit. Fix: A every 8 frames while the hidden menu waits (`battle_event_hook`), until
  the choice goes in. Tested at 30 and 60 fps, Eevee and Pikachu.

## Wild battles: the starter walking alone also battles (2026-10-24, issues #6 and #22)
- **Before.** Since 0.4.2, with the starter walking alone (or nobody), the touch went to the game's capture: the static
  battle broke (`f_7000a9ddb0` reading a null). In 0.6.0 the launcher's hint started saying so (issue #22).
- **Diagnosis.** With `f_7000a7e090` ("is it the starter?") answering no, the starter comes out of a Poké Ball
  (`ee420`) and the opening passes ("Go! Eevee!"), but Eevee does not appear and the game crashes on the first move
  (`ac2d70` via `aeb690`). The model key (`[model+0x1e0]`) stayed 0: in `f_7000a99b40` (x2 -> species u32, form u8),
  `f_7000176140` recognizes the starter (Pikachu form 8, Eevee form 1) and its branch uses the field model of whoever
  walks along, which the static battle does not have; `f_7000a9bf20` (movement switch) looks up the resource by that key
  and reads address 0. There is no `pm0133_01` (the starter's forms are field models), only `pm0133_00` / `pm0025_00`.
- **Fix.** In our battle, with the starter walking alone: `f_7000a7e090` answers no (comes out of the ball) and
  `f_7000a99b40` receives a copy of the descriptor with form 0, so the model is the species', loaded through the normal
  path (`b8b70`). 0.4.2's guard is gone; the launcher's hint has no condition again.
- **Tested** by script with a save with Eevee and Pidgey (Eevee walking alone), on Eevee and on Pikachu 1.0.0 (the same
  save): Eevee appears, moves, knockout with XP, CATCH, the hidden return with the wild one's turn and capture. Not
  tested: a Pikachu starter (form 8) on the shoulder, for lack of a save. Addresses on Pikachu: `a7e090` → `a7e0a0`,
  `a99b40` → `a99b50`.

## Wild battles: the wild one faints, and the world music playing together with the battle's (2026-10-24)
- **Symptom (user): defeating the Pokémon gave XP, but it did not faint.** It was the legendaries' rule (bit `0x80` of
  the event's `+0x574`): the knockout ends the battle with no fainting. Zeroing the bit when building (`28c770`) brings
  the game down (`ee620`, `c0000005`). The earlier attempt (above) found the nonexistent model and a wait of seconds; the
  wait was from the tests' accelerated mode (~250 frames/s): at real pace (`--turbo 0`), from the knockout to the XP
  there are ~2 s standing after the fainting. Fix: the bit stays for the opening and is removed when the command menu
  appears (`battle_event_hook`, state 4, after `ab2730`); the fainting is the trainer battles' one (`ee620`: "Rattata
  fainted!", it falls and is withdrawn). The sequence asks a model with key 0 for a joint (`f_7000a9c700`) (it is not
  the Pokémon's of either side; probably the opposing trainer's) and read the null result (`651b40`, `+0x360`); the hook
  answers "no joint", the game's own answer for a joint that does not exist. XP still goes through `9d8ae0` (the byte
  `+0x584` stays). Tested by script: Eevee (starter alone) and Pikachu (another Pokémon walking along), knockout with
  fainting and XP; the player's Pokémon defeated by a level 60 wild one also faints and the game asks for the next one
  (the "everyone fainted" case was not run to the end).
- **Symptom (user): going to and back from the capture, the world music played together with the battle's.** Music
  changes are named Wwise events, sent by `f_700016d060` (`{hash, name, size}`). The static battle sends
  `Push_BGM_field_to_battle` when it starts (`28cbec`, if `f_700016cee0` says it has not been done yet) and
  `Pop_BGM_battle_to_field` when the process ends (`28d84c`), which for us is the end of the capture. Event log: every
  capture that went back to the battle sent the Pop, and the next battle sent the Push only every other time. Fix: in a
  capture that did not catch (the battle will come back) the Pop is not sent, and neither is the next Push; the battle
  music carries on through the capture and the return. In the log, 8 returns in a row with no Pop or Push; the normal
  end (capture, knockout) sends the Pop. The tests run without sound: the user played (captures, a ball that burst and
  the return, "Back to battle", knockouts) and confirmed the music and the fainting.
- Addresses on Pikachu: `a9c700` → `a9c710`, `16d060` → `16d030`.

## Issue #21: the game closed after minutes, in the replay for the in-between images (2026-10-24)
- **Symptom.** It closes after 5 to 15 minutes (0.5.0 and 0.6.0, AMD RX 6600 XT; other reports without a log), with 60
  fps on: `c0000005` reading `0x5000000001` on a runtime thread.
- **Diagnosis.** The log has only runtime addresses; I rebuilt 0.5.0 in a worktree (same compiler) and symbolized with
  `nm`: `exec_list` inside `vk_interp_render` (replaying a frame for the in-between images), on the render thread.
- **Cause.** The replay read the command lists straight from the game's command memory, which the game reuses to record
  the next frame while the render thread replays this one. The lists' hash was checked at the start
  (`vk_interp_begin`), but the reading happened later: a half-rewritten record gave a called list (CALL) the address
  `0x5000000001`.
- **Fix.** In `vk_interp_begin` the lists are copied into a runtime buffer (`ip_list_copy`, 8 MB, doubles if short),
  with the hash computed over the copy and checked against the one from when they ran; the replay runs the copy
  (consecutive JUMPs, CALLs pointing at the copies, with a JUMP over them). The reads stay inside the guest window. A
  first wrong version: the called lists sat right after the CALL and the top list continued inside them ("0 blended").
  Tested: 2x frame generation, blending at the same levels as the runs without the change (normal variation between
  runs larger than the difference). The crash was not reproduced here; the fix is by the cause.

## Issue #24: shadow sampling on a colour texture, in battle (2026-10-24)
- **Symptom.** "Device lost" (`address ip invalid`) on an RTX 5070 Laptop in battle, when Bellsprout uses Wrap; no
  in-between images at that point (battle at 30).
- **What was found.** On the RTX 3080 Wrap does not hang. With the validation layer:
  `VUID-vkCmdDrawIndexed-None-06479`, a battle shader does a depth comparison (shadow) on an RGBA8 texture: the game
  binds a 16x16 colour texture there (format `0x25`) when it has no shadow map. On the Switch the comparison reads its
  red; on Vulkan it is undefined. (A GPU hang in a run with validation, on the summary screen, did not repeat without
  it.)
- **Fix.** A comparison slot with no depth texture receives a 1x1 depth image at 1.0 (`vk_dummy_depth_view`):
  everything lit, as against the white texture. Validation clean in battle with Wrap (3 uses); identical images.
  Whether it was the cause of the 5070's hang only the issue's author can confirm.

## 0.7.0: updating over an install asked for the game folder again (2026-10-24, fixed in 0.7.1)
- **Symptom.** With 0.7.0 unpacked over a 0.6.0 folder, the launcher showed the initial setup ("Select the extracted
  game folder"), not the rebuild.
- **Cause.** PR #26 put the CPU level into the library's id (`<id>-v3` / `-v2`); 0.6.0's (`<id>` with no suffix) no
  longer matched, `setup_ready()` became false and nothing called `setup_start(NULL)` (only the game's code, already
  handled in `gamesetup.c`). In earlier versions the id had not changed, so the case never came up.
- **How it slipped through.** The release test in the `D:\teste-0.7.0` folders never actually ran 0.7.0: their
  `lasrecomp.log` and DLLs were still the 0.6.0 copies; I did not check that before publishing. My automated attempt
  with `LARECOMP_LAUNCHER_AUTOPLAY` stayed stopped at the launcher (it only plays when it is already ready).
- **Fix (0.7.1).** `setup_needs_build()` (game files installed, a library of another version) and the launcher calls
  `setup_start(NULL)` by itself, once. Tested on a copy of the 0.6.0 folder with 0.7.1 over it: it rebuilt by itself
  (id `...-v3`) and the game ran up to gameplay.
- **Lesson.** Before publishing, check the new version's log and DLL (date and id) in the test folders, not only the
  test's answer; and test the updater's path (the previous version's folder with the new one over it).

## Trees flickering in battle with TAA (2026-10-24, not a regression)
- **Report (user, testing 0.7.1).** The vegetation flickers in battles.
- **Measurement.** Consecutive frames of a fixed battle, pixels of the upper part that go up and down (±24) over three
  frames: TAA 1.1 %, SMAA 0.05 %; SSAO Ultra changes little (0.9 % without). 0.6.0 and 0.7.1 with the battle still:
  equal (0.44–0.78 % against 0.33–1.09 %). A first comparison seemed to show it getting worse, but 0.6.0's runtime
  ignored the script's `b<N>` inputs (the battle stayed still) - compare only with scripts both versions understand.
- **Pending.** TAA on the trees' cut-out leaves in battle (with action); SMAA does not have it.

## Issue #30: "Make the 2x images" failed on an integrated AMD (2026-10-24)
- **Log.** waifu2x generated the 4708 images (exit 0), but back at 1x 2981 of the 3081 textures were far from the
  original (mean > 16): the pack was refused. At the same time the launcher warned "GPU did not finish submission within
  10 s": the shared integrated GPU could not cope with waifu2x and our drawing together.
- **What does not work.** The CPU mode of waifu2x-ncnn-vulkan 20250915 (`-g -1`) gives a segmentation fault (tested
  here, with and without `-t`).
- **Fix.** If the output fails or is refused, a second, lighter attempt: 32-pixel tiles and one thread per stage
  (`-t 32 -j 1:1:1`). On the RTX 3080 (`LARECOMP_UI2X_GENTLE=1`): 4708 images, none refused (largest error 7.35), ~5
  min. Whether it fixes the integrated AMD only the issue's author can say.

## Issue #24 in 0.7.0: full validation on Wrap, no error (2026-10-24)
- **Report.** The same crash on the RTX 5070 Laptop with 0.7.0 (no 60 fps); the GPU resets; with the integrated Intel
  it does not happen; something similar in another game's recomp.
- **Done here (RTX 3080).** A battle with Bellsprout using only Wrap: core validation, then GPU-AV (instrumented
  shaders), and GPU-AV with `LARECOMP_NO_ROBUST=1` (out-of-bounds accesses that robustness hides): no error. It points at
  the driver or the card; asked of the author: the driver version and tests turning off what only NVIDIA uses
  (`LARECOMP_WRITE_WATCH=0`, `LARECOMP_VK_NO_GMEM=1`, `LARECOMP_VERTEX_READ=copy`, `LARECOMP_ONE_QUEUE=1`).

## Issue #31: the game closed right at the start with 2002-6063 (2026-10-24)
- **Log.** Pikachu, RTX 3060 Ti: after `fsp-srv` only one RomFS read (`romfs reads: 1 (0 KB)`) and `svcBreak` with the
  result 2002-6063. The line `[fs] romfs index: N files`, which comes before in a normal run, is missing: the index of
  `extracted/romfs.bin` could not be read, so its image is invalid (truncated, or another tool's `romfs.bin` that the
  setup copied as it was); the game read a meaningless header and stopped.
- **Fix.** `romfs_image_ok` (runtime/romfs_build.c) checks the image: a 0x50-byte header, tables and data inside the
  file, and it recognizes an IVFC image. The setup refuses such an image (a new failure `SETUP_FAIL_IMAGE`, with a
  message on the start screen and the reason in the log); with the image already installed, the start screen shows that
  failure and asks for the setup again; at boot, `fs.c` stops with a clear message instead of 2002-6063. Tested: an
  image truncated at 1 MB ("tables point past its end") and one with an IVFC header stop with the message; the good image
  goes on (27818 files). I do not know yet what the issue author's image was: asked for its size and where it came from.

## 60 fps: the world "hopped" while walking, and the 1 % low (2026-10-25)
- **Report (user).** Walking sideways at 60 fps the world makes small hops to follow the character, as if out of sync;
  at 30 it does not happen. The 1 % low is bad. And a ghost of a card on the save screen (screenshot).
- **Measuring the hops.** `LARECOMP_CAM_LOG=1` (with TAA: the log comes from the motion vectors' camera), walking right
  and left at real pace (`--turbo 0`): the camera moves 6.52 cm per frame, but once per stride it gave −1.00 (only the
  fixed part of the motion, −2 cm × 0.5: the animation added nothing) and then a double step; at 30 fps, 13.04 on every
  frame. The wrong frames fell when two of the player's animation timers (`f_70005fec30`: `t += rate × step × speed`,
  `[0,40]`) wrapped around - one frame late: `39 → 40.000 (no wrap) → 1`.
- **Cause.** The world's step at 60 fps was `1e9 / 60 = 16666666` ns (integer division, `follow_setting`), which in
  float becomes a hair under 1/60: `60 × step = 0.99999994`, and the timer stopped at 39.99999 instead of 40. The game's
  at 30 is 33333334 (rounded up): it lands exactly. The `G1_60HZ` constant was already 16666667, but the rate change
  recomputed it.
- **Fix.** `g1_for(rate)` rounds up (16666667 at 60, 8333334 at 120). Measured: the lost and double steps in the
  middle of the walk are gone (the wraps land exactly, `39 → 0`, as at 30).
- **Pending.** When releasing the d-pad at 60 fps there is still a double step (12.78 cm): the braking animation starts
  (`[0,170]`) and its first frame adds one extra step; at 30 the braking is 13.04 → 4.78 → 0.
- **1 % low.** The stutters while walking (25–30 ms) coincide with new pipelines: a draw whose pipeline is still
  compiling waits up to a per-frame budget (`wait_built`), fixed at 20 ms - designed for 30 fps (27 ms of slack); at 60
  the whole frame has 16.7. Now the budget is 60 % of the frame (20 / 10 / 5 ms at 30 / 60 / 120). The same walk, second
  pass: 1 % low 40.4 → 54.6 fps, frames above 22 ms 7 → 0; skipped draws (the object appears one frame later) 74 → 441
  in ~1000 frames.
- **Ghost on the save screen.** Not reproduced: 200 in-between images with the screen still and its entry, no
  duplicated card (the largest difference to the real frame, ~400 pixels, is the character's animation).

## Wild battles at 60 fps: the return after a burst ball ran as a menu and flickered (2026-10-25)
- **Report (user).** In 60 fps mode battles stay at 30, but the one that comes back after the ball bursts stayed at 60
  and its menus flickered (a screenshot of the move menu with the Gust line duplicated).
- **Log.** In the first battle `[fps60] battle / capture: 30 fps`; on the return, `world: 60 fps` and then `menu: 30 fps
  with in-between images` until the next capture: the battle counted as a menu and got in-between images.
- **Cause.** The return is created from inside a world update (the wildbattle's `field_hook`, on the world's tick):
  `start_battle` calls `fps60_scene_begin`, but the end of that update (fps60's `field_hook`) undid the mark, and the
  world does not run again during the battle.
- **Fix.** The battle event hook reasserts the mark on every update while our battle is active. Tested at 60 fps with
  balls bursting: each return goes to `battle / capture: 30 fps` two or three frames after it starts. The hidden
  opening's limit went up from 900 to 1500 frames (a return at 60 fps reached 860 and was shown before the menu).

## Wild battles: losing did not lead to the Pokémon Center (2026-10-25)
- **Origin.** Update 1.1 of the "Wild Battles" mod on GameBanana (Rico-Santos, an IPS patch for 1.0.2) fixes "losing a
  wild battle does not take you to the Pokémon Center or home: the game goes on with the party fainted". We tested ours:
  the same bug.
- **Test.** `LARECOMP_WILDBATTLE_LOSE=1` (a new option: the player's first Pokémon at 1 HP, the others fainted). After
  the battle's lines 63 / 66, the event ends with result 0 (states 5, 6, 7, 8, 12) and the player is back in the same
  grass; in the next battle Eevee still has 0 HP.
- **Cause.** In the game's static battles the defeat is handled by the event's script, which calls the native
  `CallBattleLose_` (`f_700017e880`, in the natives table {name, function}: relocation `0x153a750`). Our battle is born
  from a touch in the world, with no script. (The mod does something else: in the post-battle function `f_700031a0d8`,
  which classifies the encounter by species - `f_7000724950` is "the species": 144/145/146/150 → 2, 100/101/111/143 → 1,
  the others → 0 -, it changes the default from 0 to 1; here that function does not even run on a defeat.)
- **Fix.** Result 0 in a battle of ours: on the next world update, what the native does -
  `f_700017f280(manager, allocator)` with the globals `[[[0x70015fad08]]+0x68]` / `[[[0x70015faab8]]+0x68]`, and the
  handle released -, without the manual fade-in. Tested: "You hurried home with your tired Pokémon...", the house, the
  mother heals the party. Pikachu: `17f280` → `17f250`.

## 60 fps: ghosts in menus and maps - menus without an in-between image (2026-10-25)
- **Report (user, screenshots).** In 60 fps mode, map icons and the save screen's cards appear duplicated and out of
  place.
- **Reproduced.** Pokédex → "Check habitat", screen still, 100 in-between images: the city icons in wrong places
  relative to the real frame (~2,300–2,800 different pixels in all of them). Identical icons, drawn with a depth test,
  go into the 3D draws' matching, which swaps their cities; the jump rule (half of the two values + 100) is loose for
  screen coordinates. A fix in the pair choice (repeating the choice when the first cbuf has several exact copies)
  changed nothing and was undone.
- **Decision (user).** Menus without an in-between image: menus, Pokédex, battles and captures at 30, as on the
  console; the world at 60. With frame generation on, menus are still interpolated (that is what it asks for).
  `LARECOMP_FPS60_MENU_INTERP=1` brings the menus' in-between image back, to compare. The dynamic resolution budget in
  menus went back to 33 ms (16.7 only with frame generation).

## Eevee update 1.0.2 with all options (2026-10-25)
- **Request.** Support the v1.0.2 update (v131072): until now it ran, but as an unknown build (`GAME_BUILD_OTHER`),
  without 60 fps, wild battles and skipping the controller screen.
- **Files.** The user's own extracted game files for the update; the setup builds `romfs.bin` from the folder (27,818
  files, like the base game).
- **What changed in `main`.** Build id `5831ec64d6b696fd`. The code moved by 0 to -0x130 depending on the section; data,
  globals and the GOT stayed at the same addresses (`.data` of the same size; the G table at `0x7000f7eeb8` and the slots
  used by the battles checked byte by byte).
- **Map.** `tools/addrmap.py` found 65 of the runtime's 69 addresses; the other 4 (the two destructors of the class A
  process, the factory `17f0a0` and the button frame constructor `aaac10`) are not unique by the masked window: by the
  neighbours' offset, checked instruction by instruction. Since `addrmap` masks the immediates of `ldr/str/add`, we also
  compared the raw instructions of the 69 functions: no struct offset changed. The generator's 3 patches
  (`tools/patches.py`) land on identical instructions.
- **Code.** `runtime/fnhook.c`: a table per build (`build_table`), `k_eevee_102`; `GAME_BUILD_EEVEE_102` in
  `runtime/gamesetup.c`; 1.0.2's `BUILD_ADDRS` in `tools/patches.py` (the generator logs "3 instruction patches moved").
  `tools/capture_loop.py` gained `DATA=<folder>` to run another install.
- **Test** (release in `D:\teste-1.0.2\Eevee`, setup from the folder, 60 fps): the world at 60 with the walking fix at
  the new addresses; a wild battle with the native CATCH, knockout ("fainted, no capture"), the capture request with
  the rate, the return to the battle after the capture scene (the same as 1.0.0 with the same script), a defeat taking
  you home, skipping the controller screen. No "no such function in this build" in the logs. The cutscenes
  (`EvCameraStart/End`) are mapped, but none ran in the tests.
- **Consequence.** `GAMELIB_ID` includes the generator (`tools/patches.py`): the release with this recompiles everyone's
  game code on the first launch, including on 1.0.0.
- **Missing.** Pikachu 1.0.2 (build `c208db6a4ef4361f`, from issue #1's log): it needs its `main` to map.

## Issues #21 / #33 / #35: the game froze after a long session (2026-10-25)
- **Reports.** #21 (RX 6600 XT): "freezes after about 10 minutes", 4 times; #35 (the same player): the image flickers
  and the game freezes; #33 (GeForce 930M): freezes in a cutscene with the music playing.
- **Signature in the logs.** All three end with no error at all, with 16,184 / 16,302 / 16,488 compilations in total in
  the session. Shortly before the end, the 2 s lines show "compile 240 ... glsl cache 240 read, 0 stored" without stopping
  (#35: 480): the same programs taken from the disk cache and compiled again every frame.
- **Cause** (`runtime/nvn/vulkan/exec.c`). The program table had 4096 positions with linear probing and, after 64 full
  positions, replaced the entry (the old `Prog` leaked): with the table loaded, two programs started evicting each other
  every frame. Each recreated program has another pointer, and the pointer is part of the pipeline key: new pipelines
  every frame. The pipeline table (8192) probed **without a limit**: when full, the loop never ends and the render thread
  spins forever - the freeze. ~8 thousand programs + ~8 thousand pipelines = the logs' ~16 thousand.
- **Fix.** Both tables double when they reach half (`Map`, `map_get` / `map_put`), without replacing or spinning; the
  log says when they grow ("[vk] program table: 4096 -> 8192 slots"). `LARECOMP_VK_MAP_START=<n>` starts small, for
  testing: with 8, they grew up to 2048 in a session with the world at 60 fps and a wild battle, normal images.
- **Also.** The log starts with the port's version ("[paths] Let's Go Recomp 0.7.6, data: ..."): in the issues' logs it
  had to be deduced from the messages.

## Issue #30: "Make the 2x images" stuck forever on an integrated AMD (2026-10-25)
- **Log.** On the first pass waifu2x returned wrong images (2986 of 3081) and our GPU work went over 10 s; the second,
  with small tiles (0.7.2), started and nothing else came out: the launcher stayed on the progress bar.
- **Fix** (`runtime/ui2x.c`). With no new image in 3 minutes, waifu2x is ended and the generation finishes as a
  failure; the warning now says the upscaler does not work on this card and that the game works the same without it.

## Issue #34: showing the FPS from the menu (2026-10-25)
- The counter already existed (`show_fps` in `larecomp.ini`, `runtime/ui/menu.mm`), with no option in the interface.
  Now it is "Show FPS" on the Graphics page (launcher and F12).

## Issues #49 / #50: blank text after choosing the language (2026-11-01)
- **Reports.** #49 (Pikachu, Intel UHD): after the language, dialogs and menus without text; the log has "guest heap
  import failed (3220 MB)". #50 (Pikachu, RTX 3050): the same symptom, no log attached: its cause is not confirmed.
- **Reproduction.** `LARECOMP_VK_NO_GMEM=1` on an RTX 3080 gives the same image: empty boxes, only the language name
  visible. The text is drawn from storage buffers (LDG), measured (`LARECOMP_LOG_GPUREADS=1`) between 1411 and 1653 MB
  inside the heap. Without the import, those reads come back zero.
- **Fix** (`runtime/nvn/vulkan/exec.c`, `gmem_info`). With the 3220 MB refused, it tries less, 256 MB at a time, down to
  512 MB. `LARECOMP_VK_GMEM_MAX_MB=<n>` simulates the limit: 2048 shows the text, 1024 does not (in both cases the image
  matches the measurement). **Limit:** a driver that only accepts less than ~1.7 GB still has no text. The log now gives
  the `VkResult`, the memory heap's size, the largest allocation and the storage buffer range. Not tested on a real
  Intel UHD.

## Issue #24: the GPU hung on a battle shader on NVIDIA (2026-11-01)
- **A fix by @steve-spiteri for smm2recomp, brought over by @Sunrase**, who tested it here: the hang went away on their
  machine. A forward conditional BRA, over a stretch with no other label, becomes an `if` instead of going through the
  `switch` (`runtime/nvn/maxwell/translate.c`). Added: a target on a scheduling word does not become an `if` (the block
  would not close). `LARECOMP_NO_BRA_IF=1` turns it off.
- **Regression.** The `mundo` battery on Eevee, 3 + 3 runs with a warm cache: before x after = 0.97 mean luma
  difference, the same as the noise between runs of the same build (1.08 / 0.95); blinks 22-25 in both. The first run,
  with a cold cache, gave a huge difference that did not repeat. The hang itself does not reproduce on the RTX 3080.

## Issue #37: the game closed at the start because of missing files (2026-11-01)
- **Log.** `romfs index: 19165 files`; all the other logs and the three images counted (Eevee 1.0.0 and 1.0.2, Pikachu
  1.0.0) have 27818. The crash is in `nn::fs::detail::FileAccessor::Read` with a null pointer: the game reads a file
  whose opening failed. The report says 0.7.1 works; that was not explained.
- **Fix** (`romfs_image_ok`, `runtime/romfs_build.c`). Fewer than 27000 files in the image's table: the setup refuses
  and asks for the game folder again, as with the unreadable image of issue #31.

## Issue #53: a crash when opening the name entry on an Intel HD 620 (2026-11-01)
- **Log.** `c0000005` in `igvk64.dll`, coming from `vkBindImageMemory` in `ImGui_ImplVulkan_CreateFontsTexture` (0.7.5's
  symbols), on the keyboard's first draw. An unproven hypothesis: the previous allocation failed for lack of memory and
  ImGui's backend went on with null memory.
- **Mitigation** (`runtime/ui/menu.mm`). The fonts' texture is created on the first frame, before the game takes the
  memory, and ImGui now logs the Vulkan calls that fail. Not tested on the report's card.
- **#52 (integrated Radeon), the same moment of the game, another signature:** a GPU fault reading address 0 right after
  the first in-between menu images. 0.7.6 removed those images from menus, but the link is a hypothesis.

## Issue #54: "the game's code did not compile" with free space (2026-11-04)
- **Log.** `generator (subsdk1) failed: [PYI-9652:ERROR] Failed to execute script 'gen' due to unhandled exception!`
  (GTX 1060, updating from 0.7.5 to 0.7.6). The launcher said "check that there are about 2 GB free", and the author had
  space.
- **What was found.** 0.7.6's `lasgen.exe` generates Eevee's and Pikachu 1.0.0's `subsdk1` with no error here (142
  chunks). The log only kept the last line of the generator's log; Python's traceback, which says where it broke, was
  left out.
- **Change.** A generator that fails copies the end of its whole log into `lasrecomp.log` (`log_tail_all`, with the
  exit code); the launcher's warning no longer blames disk space and asks for the log. The cause depends on the
  author's traceback.

## Legs "trembling" while walking with frame generation (2026-11-15)
- **Symptom.** With `frame_gen 2` (flow) at 60 and full or dynamic resolution, the player, the rival and the other
  characters seemed to stutter their legs while walking: the body slid and the step jumped, even though the window
  showed ~120 fps.
- **Diagnosis.** Window captures (`LARECOMP_WINDOW_SHOTS`) in town: every in-between image was identical to frame N
  (difference 0 on the player, the flowers and the ground), so the generation only repeated frames and the animation
  showed at 60. At 75 % it worked. `LARECOMP_FSR3_MASK_DUMP` at 100 % showed the interface mask covering the whole
  screen.
- **Cause.** `ui_snapshot_check` (`runtime/nvn/vulkan/exec.c`) only treated a scalable render target as scene when the
  scale was other than 1. At 100 % the scene's composition went through as interface, the snapshot was taken before the
  scene was drawn and the whole image differed from it: the mask covered everything and `flow_warp` returned N's pixel.
- **Fix.** Reading any `scalable` target counts as scene, whatever the scale. Now, in the middle of the step, the player
  is halfway between the frames (difference ~7 to each side, ~11 between them), the text strip's mask covers 3.6 % of
  the screen and the menu's is still full. As a bonus, in town at 60 + 2x: p99 22.9 → 17.9 ms and frames above 20 ms
  from 13 to 1 (same median, 16.8 ms).

## Menus at ~90 fps with frame generation (2026-11-15)
- **Symptom.** With 60 fps and 2x generation (flow), the X menu (and the other menus at 30) showed ~90 fps in the
  window instead of 120, and the menu itself ran at ~24 fps.
- **Diagnosis.** `LARECOMP_FRAMETIME_CSV` in the town menu: after ~4 s each menu frame started taking 41.7 ms (5
  refreshes at 120 Hz) instead of 33.3. A temporary log in `backend_present`'s image loop showed the render thread
  stopped ~35 ms per frame in `vkAcquireNextImageKHR`: 4 images per menu frame (30 x 2 x 2) did not fit. It did not
  change with more images in the swapchain (11), with the images' delay (`ip_lead`) capped at 4 or 8 ms, or with the
  flow work removed. With 2 images per frame (`LARECOMP_INTERP_MULT=2`) the menu stayed at 33.3 ms.
- **Cause.** In the menu the interface mask covers the whole screen, so the 3 in-between images were copies of N; and
  presenting 4 images per 33 ms frame on this driver (Intel Arc, windowed, fifo) holds the acquisition of the window's
  images beyond the frame time.
- **Fix** (`runtime/nvn/vulkan/exec.c`, `vk_interp_begin` / `flow_image`). In menus (`fps60_menu`) with flow, N's
  processed image appears 2 times per frame, without flow or warp. The menu goes back to the game's 30 (median 33.3 ms,
  max 34.9) and the window stays at a constant 60, with the same image as before. `LARECOMP_FG_MENU_FLOW=1` restores the
  previous behaviour for comparison.

## Frame generation: presenting on time from a present thread (2026-11-15, in progress)
- **Symptom.** With 2x generation the render thread waited ~11-12 ms of every 16.7 ms world frame in
  `vkAcquireNextImageKHR` (this Intel driver, fifo), and in-between images were presented up to ~16 ms late.
- **Change** (`runtime/nvn/vulkan/device.c`). With frame generation the render thread draws into 8 images of its own
  (`owin`); a present thread acquires a window image ahead of time (`pt_pre`), copies on the transfer queue (family 2)
  and presents at the due time (`present_offscreen`). Presents now arrive ~0.4 ms late, and the window shows 120.
  `LARECOMP_FG_DIRECT_ACQUIRE=1` restores the old path (the render thread acquires and draws into window images);
  `LARECOMP_FG_NO_COPY_QUEUE=1` copies on the graphics family.
- **Open.** Menus still skip ~4 images/s when the presents lock to the refresh at a bad phase; `lead_adapt` on this
  path made the lead swing 0.5-16 ms and must be reconsidered; a temporary `TMPP` log line (`TMP_PT_LOG`) is still in
  `present_offscreen`.

## The FPS counter counted only the game's frames (2026-11-15)
- **Symptom.** With 2x generation the user saw 50-60 on the counter while the window showed ~120.
- **Cause.** The `show_fps` counter (`runtime/ui/menu.mm`) showed ImGui's `io.Framerate`, the game's frames.
- **Fix.** The counter shows the images reaching the window (`vk_ui_fps()`, `runtime/nvn/vulkan/device.c`) and, when
  higher, the game's frames as well: "120 fps (60 drawn)".
