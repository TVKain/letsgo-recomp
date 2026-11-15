# Debugging tools

Everything used to diagnose the port. The environment variables apply to `build/lasrecomp.exe` (in Git Bash:
`LARECOMP_X=1 ./build/lasrecomp.exe extracted --play`).

## Running and input
| Variable | Effect |
|---|---|
| `LARECOMP_INPUT="frame:BUTTON:frames,..."` | scripted input (A, B, X, Y, L, R, PLUS, MINUS, directions, STICK_*). Turns off the real controller during the test |
| `LARECOMP_NPAD=handheld\|fullkey\|dual\|left\|right` | how the PC controller appears to the game (default: `handheld`) |
| `LARECOMP_FPS=<n>` | forces n fps (default: the game's interval, 30 fps; `0` = uncapped) |
| `LARECOMP_NO_AUDIO=1` | no audio (automated tests) |
| `LARECOMP_FONT=<file>` | the system font given to the game instead of the default list (`runtime/hle/pl.c`; Yu Gothic Regular on some Win10 installs crashes the font engine, issue #1) |
| `LARECOMP_LANG=en\|pt\|ru` | the overlay menu's language (closing the game, the name keyboard); without it, the system's language |
| `LARECOMP_MENU_KEY=<key>` | another key for the settings menu (default `F12`; an SDL scancode name: `F10`, `Insert`...) |
| `LARECOMP_SWKBD_UTF8=1` | the keyboard returns UTF-8 instead of UTF-16 |
| `LARECOMP_SWKBD_TEXT=<text>` | the keyboard answers this text without opening the overlay menu: a scripted new game gets past the name choice (scripted input ignores the real keyboard, and the script used to stop there) |
| `LARECOMP_GYRO_TEST=x\|y\|z` | the virtual gyro oscillating ±15° on the given axis (`z+` / `x-`...: a 10° turn ramped over 1 s after aiming starts); logs when the game reads the sensor. To reach a capture: walk through grass (`STICK_*`) and press A at "Get ready"; the encounter is random, repeat until the log has `sensor started` |
| `mod` / `game_lang` (larecomp.ini) | the active mod (`mods/<name>/`, the log shows `[mods]` and how many romfs files were replaced) / the language asked of the system (`en-US`, `es`...; an existing save keeps its own) |
| `LARECOMP_LOG_FILES=1` | every romfs file the game reads (finding where a text or image lives, for a mod) |
| `LARECOMP_TOUCH=<from>-<to>[@x,y[,width]]` | a finger moving back and forth around x,y (pixels of the 1920x1080 screen; width 0 = still) between those frames; `@x,y>x2,y2` drags; several segments with `;`. Logs `[touch]`: start and end of the touch, gestures and who reads them. Play with Eevee: `1440:X:6,1490:UP:6,1530:A:6,1640:A:6,1700:A:6`; petting the forehead `1760-1960@960,375`; berry button `@1807,952,0`. The controller's finger in the script: `RSTICK_*` and `ZR` |
| `SAVE=<savedata.bin or folder> tools/repro.sh ...` | runs the test with another save (copied to `build/test-save`; the player's `save/` is not touched). `LARECOMP_INPUT` timings change from one save to another (tutorials seen or not) |
| `TURBO=0 tools/repro.sh ...` | `repro.sh` runs in turbo by default (`LARECOMP_FPS=0`, ~4x faster: the frames are the same, only idle animations tied to real time change phase); `TURBO=0` goes back to real speed, to measure fps or audio |
| `LARECOMP_DRAW_CHAINS=<frame>[-<last>]` | logs each draw, list recording (`begin`) and list call (`call`) in those frames, with the game's function chain (`[chain]`) |
| `LARECOMP_HOOK_DUMP_FRAMES=<first>-<last>` | limits `LARECOMP_HOOK_DUMP` to those frames |
| `LARECOMP_ELAPSED_LOG="<function>:<step>,..."` (+ `LARECOMP_TIME_PROBE_FRAMES=<from>-<to>`) | the time step (ns) each function receives from the timers object, with the object and the getter (docs/RESEARCH-60FPS.md, "Time map") |
| `LARECOMP_TIMER_USERS=<from>-<to>` | who reads each time step (calls to the getter `f_70000395f0` by return address), listed on the last frame |
| `tools/teste60.sh <captura\|batalha> <0\|1\|2>` | the same scene at 30 fps and in a 60 mode, with images at the same game time (`build/teste60/<scene>-<mode>/sheet.png`) |
| Warning | `fnhook` keeps **one hook per address**: the last registered wins; two probes on the same function cancel each other |
| `LARECOMP_DAYS_AHEAD=<n>` | the clock n days ahead (daily things: the partner's hunger, which must be above zero for it to eat) |
| `LARECOMP_WILDBATTLE=1` (+ `LARECOMP_WILDBATTLE_*`) | wild battles (docs/BATTLE-MODE.md; the launcher turns it on the same way). `SPECIES=<n>`/`LEVEL=<n>`: always that Pokémon (default: the one touched); `MOVES=a,b,c,d`: those moves (default: by level); `MAX=<n>`: battles per run (default: all); `FADEIN=0` turns off the manual fade-in, `FADE_TYPE`/`FADE_DELAY`/`FADE_FRAMES` tune it; `LOGPOKE=1` logs the fields of the Pokémon's object (`=2` writes `build/poke_<frame>.bin`); `STATE_LOG=1` the states of the process and of the battle event (with the result); `DEBUG=1` saves the passes of a frame 240 frames after the battle; `USECFG=1` (experimental, crashes the game) launches the constructor's configuration. Catching during the battle (step 6): `AUTOCATCH=<n>` turns the n-th menu choice in each battle into a capture request (tests without touching the button); `FORCE_RATE=<n>` answers that catch rate (1 to fail, 255 to catch); `HP=<n>` starts the wild Pokémon with n HP (a one-hit knockout, to test XP); `LOSE=1` starts the player's first Pokémon with 1 HP and the others fainted (a loss); `THEIRTURN=1` makes every return from the capture start with the wild Pokémon's turn (normally only after a ball that burst); `CATCH_MENU=0` serves the original menu even in the mode's battles (the trainer battles' path); `CATCH_DUMP=<folder>` saves the menu files assembled at boot there; `CATCHLOG=1` who asks for the catch rate; `HPLOG=1` each battle Pokémon built and returned (HP, status, id); `MENULOG=1` the menu (the CATCH button wired, the choices); `MSGLOG=1` the decrypted lines in our battles; `HPSCAN=<A>:<B>[:<C>]` (+ `HPSCAN_HP`) searched memory for the HP |
| `LARECOMP_VK_MAP_START=<n>` | the program and pipeline tables (`runtime/nvn/vulkan/exec.c`) start with n slots (default 4096 / 8192) and double at half full: to test growth (the log shows each "table: a -> b slots") |
| `LARECOMP_SKIP_CONTROLLER=0/1` | no controller selection screen at the start (the launcher sets the same: `skip_controller`); `runtime/hle/controller_skip.c` |
| `LARECOMP_CUTSCENE_LOG=1` | logs the start and end of each cutscene (`[cutscene]`: the script natives `EvCameraStart` / `EvCameraEnd`; `runtime/hle/cutscene.c`): there and on the title screen SSAO goes to half |
| `LARECOMP_IMAGE_DUMP=<file>` | writes the `main` module as loaded and relocated (base `0x7000000000`): to read the executable without the NSO tools (the script natives table, strings) |
| `LARECOMP_INPUT` with `b<N>:<button>:<len>` / `c<N>:...` | inputs counted from the start of the wild battle / of the capture after it (the encounter's frame changes every run); after the mark, the absolute inputs stop |
| `LARECOMP_FNPROF=b<from>:<to>` | the function profile window counted from the start of the wild battle |
| `LARECOMP_WATCH_READ=1` | `LARECOMP_WATCH`'s watch catches reads too (the page becomes inaccessible) |
| `LARECOMP_WATCH=<addr>[,<addr>...]` | a write watch (Windows, `runtime/hle/memwatch.c`): protects the page of those addresses (32-bit words) and, on each write to them, logs the writer's backtrace (the game's functions as `f_<address>`). Heap addresses **do not repeat between runs** |
| `LARECOMP_WATCH_PARTY=<frame>` + `LARECOMP_WATCH_SPECIES=133:10,16:9,...` | searches the heap for 0x104-byte records in PB7 format (species u16 at `+8`, XP u32 at `+0x10`, level at `+0xEC`) and watches each one's XP. The heuristic finds many false positives (the in-memory structure may not be raw PB7) |
| `LARECOMP_SNAP=<frame A>,<frame B>` | copies the heap's non-zero pages at A and, every 250 frames from B (30 times), lists the most common small deltas of the words that grew (3 to 20 hits) with sample addresses; a party's XP gain is a shared delta. The heap has many counters changing, so the noise is large |
| `LARECOMP_GYRO_AXES=<yaw><pitch>` | the virtual gyro's axes moved by the mouse (default `zx`) |
| `mouse_sens` (larecomp.ini) | degrees of turn per mouse pixel (default 0.1) |
| `LARECOMP_LAUNCHER_TAB=<n>` | the launcher opened on page n (0 Game, 1 Graphics, 2 Image and sound, 3 Controls, 4 Mods; with `LARECOMP_LAUNCHER_SHOT`) |
| `LARECOMP_LAUNCHER_KEYS=1` / `<slot>` / `<slot>:<key>` | the launcher on the "Controls" page / waiting for the key of action `slot` (`BIND_*` in runtime/input_bind.h) / pressing that key (with `LARECOMP_LAUNCHER_SHOT`) |

## Hangs and crashes
| Tool | Use |
|---|---|
| Crash backtrace | the game's functions show as `f_<address>`; `svcBreak` shows the `nn::Result` |
| `LARECOMP_THREAD_DUMP=<s>[,<repeat s>]` | lists each thread: the svc it is blocked in, arguments and the guest stack |
| `LARECOMP_TRACE_SVC=1` | logs every system call (very high volume) |
| `LARECOMP_PROF_SVC=1` | every 2 s, per guest thread: system calls (`svc`), how many and how long each blocked (`[svcprof]`) |
| `LARECOMP_PROF_CONDVAR=1` | every 2 s, the game's condition waits (`WaitProcessWideKeyAtomic`) by duration and the mean latency between the signal and the thread running again (`[condvar]`) |
| `LARECOMP_PROF_LOCKS=1` | every 2 s, the game's most contended mutexes (`ArbitrateLock` that had to wait): address, waits, time and the guest stack of the first (`[locks]`; resolve with `tools/addr2sym.py`) |
| `LARECOMP_GPUPROF_AT=<frame>[,<frame>...]` | GPU time per pass, copy and dispatch of those frames (`[gpuprof]`; the header carries the frame number). With `LARECOMP_GPUPROF_DRAWS=1`, a timestamp before each draw (one line per draw: vertex program, hash and address of the fragment shader, indices, instances); with `LARECOMP_GPUPROF_STATS=1` also each draw's pipeline statistics (`ia`, `vsinv`, `clipprim`, `fsinv`). The timestamps serialize the GPU: they serve to compare draws with each other, and the total runs a little over the real one. Our passes have a line each (`ours: camera motion vectors`, `GI`, `GI trace`, `GI blur, temporal`, `GI composite`, `SSAO`, `contact shadows`, `post`, `FSR 3.1`, `present to the window, menus`); `(submission end ...)` closes each submission. Before, the "SSAO" line measured the motion vectors and the GI one included SSAO, and the frame's last pass (FSR 3.1, the presentation) did not show |
| `LARECOMP_EXP_VS=<vertex program address, hex>` + `LARECOMP_EXP_MODE=skip\|scissor\|half` | research: in that program's draws, do not draw, draw with a 1x1 scissor (no pixels, only vertices) or with half the instances. `LARECOMP_EXP_ALT=1` only on odd frames, to have both versions of the same scene in the same run (see [RESEARCH-GPU.md](RESEARCH-GPU.md): comparing separate runs misleads) |
| `LARECOMP_EXP_VS_EARLY=<address>[:<pc, hex>]` | research: that program's vertex shader returns at the start of `main`, or before the instruction at `pc` (the `pc` only exists in the GLSL with `LARECOMP_SAVE_MSL=1`) |
| `LARECOMP_GLSL_OVERRIDE_DIR=<folder>` | research: `<folder>/<vertex program address, hex>_vs.glsl` replaces the generated GLSL (start from `build/glsl/`, written by `LARECOMP_SAVE_MSL=1`) |
| `LARECOMP_NO_ROBUST=1` | research: turns off Vulkan's `robustBufferAccess` |
| `LARECOMP_VERTEX_READ=direct\|copy\|auto` | where the GPU reads the draws' vertices and indices from: `direct` = in place, from the game's imported memory (over PCIe on a discrete card); `copy` = a copy in VRAM; `auto` (default) = a copy on a discrete card, in place on an integrated one. Ranges a compute writes always stay in place ([RESEARCH-GPU.md](RESEARCH-GPU.md)). The statistics line has `vertex ranges N copied, M in place` |
| `LARECOMP_RENDER_THREAD=0\|1` | the Vulkan backend's render thread (on by default; `render_thread = 0` in `larecomp.ini` also turns it off). `vertex_read = auto\|copy\|direct` in the ini is the same as `LARECOMP_VERTEX_READ`. `LARECOMP_HEAL_KEYS=1`: F5 makes every texture recheck memory, F6 reads all vertices in place (research, HISTORY 60) |
| `LARECOMP_INTERP=1` + `LARECOMP_INTERP_MULT=<k>` | research: replay interpolation always on, with k fixed images per present (2..8; without `_MULT`, 2). The F12 menu's frame generation (`frame_gen = 2 / 3 / 4`) uses the same interpolation with k chosen by each frame's pace. `LARECOMP_WINDOW_SHOTS` writes `mid1`..`mid<k−1>` and `fin` (with k = 2, `mid`). Results: docs/RESEARCH-60FPS.md, "A free multiplier" |
| `LARECOMP_FG_AT=<present>:<k>,...` | changes frame generation to k (0, 1 = Auto, 2, 3, 4) at those presents, like the F12 menu |
| `LARECOMP_FG_DISPLAY_HZ=<hz>` | (research) Auto frame generation picks the multiplier as if the screen had this refresh rate (without it: the Windows compositor's, `[fg] auto: ...` in the log) |
| `LARECOMP_FG_VRR=1` | the screen has a variable refresh rate (G-Sync / FreeSync): the scheduled images leave the refresh grid and Auto picks the largest multiplier up to the refresh rate, without requiring it to divide evenly |
| `LARECOMP_FG_SCALE=<f>` | (research) the in-between images rendered at f times the real frames' size on each axis (0.25..1; without it, full size - or, in Auto, 75 % / 50 % when the GPU cannot keep up, before lowering the multiplier: `[fg] auto: ...`). A render target the replay reads before drawing is filled from the full-size one (`[vk] reduced in-between images: ...`) |
| `LARECOMP_LO_SHARP=<stops>` + `LARECOMP_LO_HIST=<weight>` | (research) the reduced in-between images without FSR 3.1, redone against N's image: the RCAS strength afterwards (stops; negative: no RCAS; default 1 at 75 % and 0.9 at 50 % with SMAA, 1.3 and 1.15 with TAA) and the weight of N's image (default 0.9) |
| `LARECOMP_PRESENT_LOG=<file>` | a CSV with each window image: the present, when the call returned and when it reached the screen (`VK_KHR_present_wait`, on a separate thread): `id,frame,image,nimg,present_ms,shown_ms`. Shows frame generation's pacing as it is seen |
| `LARECOMP_PENDING_LOG=1` | each scheduled image (frame generation) as it is shown: its delay past its time and the learned lead (`lead`) |
| `LARECOMP_FLOW_MATCH=0` | (comparison) optical flow frame generation (`fg_method = flow`) with only the renderer's motion vectors (camera and objects), without the block matching on luminance that corrects them where they do not match the image (shadows moving over still ground, particles, water, reflections). In the grass walk at 720p, 2x: flicker 0.76 → 1.10 % of blocks |
| `LARECOMP_FLOW_RADIUS=<px>` | (research) the reach of the optical flow's block matching search in luminance pixels (~640 wide, at any resolution), in steps of 2 around the analytic vector (default 4) |
| `LARECOMP_FLOW_OCCLUSION=0` | (comparison) optical flow without N-1's depth test: a point found in N always blends with N-1 where it was, even if something closer covered it in N-1 |
| `LARECOMP_FLOW_SHARP=<k>` | (research) the strength of the sharpening after optical flow's blend of N-1 and N (default 0.2; 0 turns it off: −9 % of detail against the real frames, 0.5: +13 %) |
| `LARECOMP_FLOW_DEBUG=1` | optical flow's in-between images tinted: red where block matching replaced the analytic vector, green where only N (the point was covered in N-1), blue where only N-1 (uncovered after t) |
| `LARECOMP_FG_GPULAG=1` | (research) at each present with frame generation, waits for the GPU and logs how long after the present it finished the images (`[gpulag]`); the wait spoils the pacing, for measuring only |
| `LARECOMP_FG_DRAW_AT_TIME=1` | (comparison) the scheduled images are drawn at their own time again, on the main queue, as before the presentation queue |
| `LARECOMP_FG_MENU_FLOW=1` | (comparison) in menus, optical flow and k images per frame as before; without it, frame N's image appears twice per menu frame (the interface mask covers the screen, the in-between images came out equal to N) |
| `LARECOMP_FG_DIRECT_ACQUIRE=1` | (comparison) with frame generation, the render thread acquires the window images and draws into them directly, as before; without it, it draws into 8 images of its own and the present thread acquires a window image ahead, copies into it on the transfer queue and presents at the due time (`present_offscreen` in `device.c`) |
| `LARECOMP_FG_NO_COPY_QUEUE=1` | (comparison) the present thread's copies go on the graphics queue family instead of a separate transfer family that can present |
| `LARECOMP_ONE_QUEUE=1` | (comparison) without the second queue: the images drawn earlier are presented from the main queue |
| `LARECOMP_FG_NO_VSYNC_GRID=1` | (comparison) the scheduled images off the monitor's refresh grid (`DwmGetCompositionTimingInfo`) |
| `LARECOMP_SIDE_SHARP_STOPS=<stops>` | (research) the in-between images' RCAS with FSR 3.1: that many stops weaker than FSR's (default 0.6 at full size, 0.2 at 75 %, 0.05 at 50 %) |
| `LARECOMP_INTERP_REJ_LOG=1` | each present without in-between images and the reason (`[interp-rej]`, `[interp-cut]`) and each object kept at frame N (`[interp-obj]`: the fraction of its words that changed a lot; above `LARECOMP_INTERP_OBJ_LIMIT`, default 0.4, it is not blended) |
| `LARECOMP_INTERP_JUMP_ABS=<units>` | (research) the absolute term of a word's jump between N-1 and N (default 100; it was 4): above half its size and this, the word - and the whole buffer - stays at frame N |
| `LARECOMP_INTERP_TFIX=<t>` | (research) every in-between image at this t: with 1 they should be identical to frame N (checks the replay), with 0 to frame N-1 (what does not match is what does not blend well) |
| `LARECOMP_INTERP_DROP=<mask>` | (research) the in-between images leave out the 3D draws that kept frame N's constants for these reasons (2 no pair, 4 object rejected, 8 jump): what vanishes shows what they are |
| `LARECOMP_INTERP_KEEP_OBJ=<object hex>` | (research) that object's draws stay at frame N in the in-between images |
| `LARECOMP_INTERP_FAR_LOG=<units>` | (research) logs each blended buffer that ended up further than this from frame N (`[interp-far]`: the render target's width, the word, N-1, N, the blend and the draw): a wrong pair shows as a big jump where the rest moves little |
| `LARECOMP_INTERP_SIG_LOG=<present>:<size>` + `LARECOMP_INTERP_SIG_ARGS=<text>` + `LARECOMP_INTERP_SIG_DUMP=<n>` | (research) the identity (program, vertex buffer, object, arguments) of each draw that binds a cbuf of that size - or, with `_ARGS`, of every draw whose identity contains that text - at that present and the next; with `_DUMP`, the words of the first n |
| `LARECOMP_INTERP_NO_HELD=1` | (comparison) held values that change (sprite frame, expression) are blended again instead of switched in the middle |
| `LARECOMP_INTERP_ALL3D=1` | (research) every draw is blended as 3D, the interface too |
| `LARECOMP_INTERP_KEPT_LOG=<present>[:<last>]` | (research) in the first in-between image of those presents, each cbuf that stayed at frame N and the reason (`2d`, `rejected`, `no-match`, `jump`, with the word), how much it changed since its pair in N-1 (a draw in N that changed is movement at the game's cadence), the 2D buffers blended and how many words stayed at N, and (with `LARECOMP_INTERP_VTX=1`) each small vertex stream (`[interp-kept]`) |
| `LARECOMP_INTERP_VTX=1` | (research, off) the small vertex streams (up to 64 KB) of blended draws recorded with the frame and blended in the replay: the position of a vertex stream, all float attributes of a per-instance stream. Not worth it: the flowers already come halfway through the cbufs, and grass tufts vanished in an in-between image (streams of another tuft of the same size) |
| `LARECOMP_INTERP_KEEP_SIG=<text>[\|<text>...]` | (research) draws whose identity (as `LARECOMP_INTERP_SIG_LOG` writes it: program, vertex buffer, object, arguments) contains one of these texts keep frame N's constants |
| `LARECOMP_INTERP_KEEP_RT=<width>` | (research) draws into a render target of this width (the game's: 2048 = the shadow map) stay at frame N |
| `LARECOMP_INTERP_RT_DUMP=<present>:<width>` + `LARECOMP_INTERP_RT_DUMP_DIR=<folder>` | (research) each pass into a render target of that width at that present, of the real frame and the in-between images: colour in `build/frames/rt_<present>_<image>_<n>.png` and depth as PGM (stretched over its range) in the folder (default `build/frames`, which `scenario_shot.sh` does not copy) |
| `LARECOMP_INTERP_OTHER_COPY=0` | (comparison) a draw paired by content with another copy of the same object (a word that changes by more than a quarter of both values and 50 units) is blended with it again: bush shadows where there are none |
| `LARECOMP_INTERP_ONE_TO_ONE=0` | (comparison) a draw in N-1 can again be the pair of several draws in N (without it, only of the closest; the others stay at frame N): the new copy of a repeated object is drawn in place of another copy again |
| `LARECOMP_INTERP_SIBLING=0` | (comparison) the copy of an object that enters the scene without a pair in N-1 stays whole at frame N again (with N's camera) instead of changing, word by word, like its closest copy that has a pair |
| `LARECOMP_INTERP_SLERP=0` | (comparison) matrices that turn more than 3 degrees between N-1 and N are blended term by term again, instead of along the arc (the turn with Rodrigues, scale and translation in a straight line) |
| `LARECOMP_INTERP_NO_ALT=1` | (comparison) vec4s that return to N-2's value (alternating between two states) are blended again instead of staying at N |
| `LARECOMP_INTERP_CURVE=0` | (comparison) the in-between images go back to the straight line from N-1 to N, without the curve through N-2, N-1 and N |
| `LARECOMP_INTERP_PLAN=0` / `=2` | (comparison / validation) 0: each in-between image decides each cbuf's blend again, instead of using the one decided in the present's first (`ip_plan_*`); 2: both, compared (`[interp-plan]`: differing words, the largest relative difference, cbufs kept by one and blended by the other) |
| `LARECOMP_INTERP_VTX_MEMO=0` | (comparison) the replays read and copy each draw's indices and vertices again, instead of using frame N's (`vtx_memo`; `[interp]` logs how many were reused and how many copied again) |
| `LARECOMP_INTERP_UI_KEEP=0` | (comparison) the in-between images resolve the interface against N's image through the scene's motion vectors again (with FSR 3.1 or reduced: doubled text in battles); without it, where N's interface mask says interface, N's image at the same place (`ip_ui_keep`) |
| `LARECOMP_FSR3_UI_COMPOSITE=0` | (comparison) the interface comes out of FSR 3.1 as part of the jittered scene again (at 4K, a pixel of shake every frame); without it, where the mask says interface, the image given to FSR in Catmull-Rom (`ui_composite.frag`) |
| `LARECOMP_POOL_FIX=0` | back to the texture pool's old behaviour (the slot in the host object freed), only counting in the `[nvn] texture pool: ...` log (HISTORY 60) |
| `LARECOMP_INPUT_LOOP=<start>:<period>` | with `LARECOMP_INPUT`, repeats the inputs of `[start, start + period)` forever; after each battle / capture it stands still 300 frames, and inside the encounter it flees (B, down three times, A). Used by `tools/capture_loop.py run <name>` / `scan <name>` (before/after pairs of each encounter in `build/capture_loop/<name>/`). `LARECOMP_INPUT_LOOP_CATCH=1`: inside the encounter press A every 40 frames instead of fleeing (gets ready, throws and passes the capture's screens: experience, Pokédex). In `capture_loop.py`, `--leg <frames>` lengthens each leg of the walk (300 crosses parts of the area; the default 80 stays in the same grass) and `EXE=<path>` runs another build |
| `LARECOMP_SHOT_RAW=<file>` + `LARECOMP_SHOT_RAW_LAST=<frame>` | the `LARECOMP_SCREENSHOT_EVERY/FROM` series goes to a raw file (480x270 RGB per frame, no PNG) and the game exits at the last frame; read by `tools/bateria_scan.py` |
| `LARECOMP_EXIT_AT_PRESENT=<n>` | with `LARECOMP_FRAMETIME_CSV`, exits at present n; used by `tools/perf_ab.py` |
| `tools/perf_ab.py ... --mode 120` / variant `NAME=INI=<line>;<line>` / `SHOW_FPS=1` | 120 fps mode in the world; `larecomp.ini` lines after the default ones (`"q75=INI=resolution = 75%"`); the fps counter in the window during the test. Without `extracted-pikachu/`, `pikachu` uses `extracted/` |
| `LARECOMP_VK_PRESENT=fifo\|immediate\|mailbox` | the present mode; the log says the one chosen and the ones the driver offers (`[vk] present mode`). Intel's driver on Windows (Arc 140V) only offers `immediate` and `fifo`: without `mailbox`, it stays `fifo` |
| `LARECOMP_GAME_CPU=v2` | on a CPU with AVX2, the game's code is built (and only loads) for x86-64-v2, as on a CPU without AVX2: the fused operations emulated (`simd_fp.h` `FFMA`). To measure the cost without an old machine: the start screen recompiles the game's code; removing the variable recompiles it again for v3 |
| `EXE=<exe> tools/bateria.sh ...` / variant `B=EXE=<exe>,LARECOMP_GAME_LIB=<dll>` in `tools/perf_ab.py` | runs another build of the runtime (a reference one built separately, e.g. `git worktree add ../lg-base HEAD` + `make build/lasrecomp.exe` there, copied to `build/base/`); in the battery, Eevee then uses `build/lasgame.dll` by path. A DLL only loads with the exe of the same `GAMELIB_ID` |
| `LARECOMP_PIPE_STATS=<vertex program, hex>\|all` | what the driver reports about each compiled shader (registers, spills, code size: `[pipestats]`) and the program's vertex attribute layout (`VK_KHR_pipeline_executable_properties`) |
| `LARECOMP_LOG_VCOPY=1` (with `LARECOMP_GPUPROF_AT`) | one line per vertex stream copy in the profiled frames: bytes asked for, size of the bound buffer, stride, max index |
| `LARECOMP_VK_KEEP_VERTICES=0` | vertices are copied to VRAM every frame again (default: a copy is kept and reused as long as the game does not write to its pages; off where the platform does not track writes). With `LARECOMP_VK_PROF`, the line shows the copies read, new, rewritten by the game (they go to the ring) and out of space |
| `LARECOMP_WRITE_WATCH=0` / `=1` | the game's heap is reserved without / with Windows' written-page tracking (`MEM_WRITE_WATCH`), which the vertex cache depends on. Without the variable: on only when the main video adapter is NVIDIA (the only one tested) |
| `LARECOMP_VK_ASYNC_COPY=0` | vertex and index copies to VRAM are done by the render thread again (default: two helper threads do the ones of 32 KB or more; off with fewer than 4 logical processors) |
| `LARECOMP_VCOPY_SAME=1` (with `LARECOMP_VK_PROF`) | research: how many copied vertex bytes were equal to the previous copy of the same range (a hash per range; costs as much as the copy) |
| `LARECOMP_FRAME_FINISH=1` | with the render thread, the `nvnQueueFinish` of the game's frame loop (which it calls when it measured under 4 ms of GPU in the previous frame) waits for the queue and the GPU again; without it, it follows the game's own slow-GPU path (HISTORY, "the Finish of every frame") |
| `LARECOMP_VK_COPY_WAIT=1` | the game's buffer copies (`CopyBufferToBuffer`) always wait for the GPU again (as before 0.5.1); without it, they only wait when the GPU writes the source or the destination, or reads the destination straight from memory |
| `LARECOMP_LOG_B2B=1` | the first 60 buffer copies: source, destination, size and whether they waited for the GPU (`[b2b]`) |
| `LARECOMP_LOG_GPUREADS=1` | logs each memory range a global memory shader may read (bound storage buffers) |
| `LARECOMP_VK_NO_GMEM=1` / `LARECOMP_VK_GMEM_MAX_MB=<n>` | without importing the heap (the game's text vanishes, issue #49) / refuses imports larger than n MB, as a driver would |
| `LARECOMP_NO_BRA_IF=1` | every BRA goes through the shader's `switch`, without becoming an `if` (issue #24) |
| `LARECOMP_LOG_GPUWRITES=1` | logs each memory range a compute may write (bound storage buffers) as it enters the set |
| `LARECOMP_HLE_WHO=<fake address, hex>[,...]` | at boot, prints the name of the host function behind a `0x70800000xx` address seen in a `LARECOMP_THREAD_DUMP` |
| `LARECOMP_LOCK_SPIN_US=<n>` | how long a thread spins on a contended mutex before sleeping (default 40; 0 = always sleeps, as before; off with fewer than 4 logical processors). To compare before/after in the same binary |
| `tools/addr2sym.py <address> [-d <bytes>]` | module, nearest symbol and disassembly of a guest address |
| `tools/addrmap.py <main from> <main to> <address>... [d:<data>]` | the same code (or data) in another build of `main` (Eevee <-> Pikachu, an update): compares the instructions with the relative fields masked until only one matches. The runtime's addresses go in `runtime/fnhook.c` and `tools/patches.py` (parity rule, CLAUDE.md) |
| `nm build/lasrecomp.exe` | the runtime's symbols for `lasrecomp+0x...` addresses |

## Graphics
| Variable | Effect |
|---|---|
| `LARECOMP_SHOT_AT=<frame>,...` | saves the game's frame to `build/frames/frame_N.png` |
| `LARECOMP_MV_DUMP=<frame>,...` | saves that frame's camera motion vectors to `build/frames/mv_N.png` (RGBA8: 0.5 + 32 × velocity in uv; the image comes out flipped in y like the `frame_N.png`). `tools/mv_check.py build/frames N` checks them: reprojects the previous frame with them and compares the error |
| `LARECOMP_SSAO_DUMP=<frame>,...` | saves the occlusion (SSAO) as applied in that frame, after the blur and the history, to `build/frames/ao_N.png`. `tools/ssao_temporal_check.py <without> <with>` compares two runs with the same input (accumulation off / on): ghosting (temporal darker > 2%) and noise; `tools/ssao_temporal_sheet.py` builds enlarged crops with the difference |
| `LARECOMP_GI_DEBUG_EXPOSURE=<x>` | exposure of the advanced menu's "indirect light only" (GI) view; default 16 (the game's HDR scene is dark before its exposure) |
| `LARECOMP_MVO_PROBE=<frame>` | logs, for each draw with per-object vectors in that frame, the previous frame's constant blocks: identical, missing (`MISSING`) or rejected by a jump (`REJECTED`, with the word and the values) |
| `LARECOMP_FSR3_MASK_DUMP=<frame>` | saves that frame's interface mask (the one FSR 3.1 receives, and with frame generation the in-between images'; with it, the present number) to `build/frames/uimask_N.png` |
| `LARECOMP_CAM_LOG=1` | the camera's position in the world (cm) every real frame (`[cam] present N pos x y z`) and each in-between image's (`[cam] present N t T pos x y z`: between the previous real frame and this present's; needs motion vectors: TAA, FSR 3.1, SSAO or GI). The camera follows the player: `tools/walk_speed.sh` measures walking speed in game time with this |
| `LARECOMP_FPS60_NOWALKFIX=1` | turns off the fix for walking and turning speed at 60 / 120 fps (`fps60.c`, "the player's walking") |
| `LARECOMP_STEP_SCALE=<fn>:<factor>,...` | (research) the timers' step 1 multiplied while those functions run (addresses of the build in use); `LARECOMP_STEP_SCALE_LOG=<present>` logs the fields +0x494..+0x49c of x0 |
| `LARECOMP_FARG_SCALE=<fn>:<factor>,...` | (research) the first float argument (s0) of those functions multiplied; `LARECOMP_FARG_LOG=<present>` logs the animation player at x0+0x120 |
| `LARECOMP_FIND_MOVER=<present>` | (research) in the objects passed to `LARECOMP_STEP_SCALE`, the float triples that move 1–20 cm per update (a position); `LARECOMP_FIND_MOVER_DUMP=<file>` writes each object's 0x1000 bytes |
| `LARECOMP_FNWATCH=<address>` + `LARECOMP_FNWATCH_FNS=<fn>,...` | (research) logs when the float changes during one of those functions (with several threads, the function may not be the writer: prefer `LARECOMP_WATCH`) |
| `LARECOMP_WATCH_AT=<present>`, `LARECOMP_WATCH_MAX=<n>`, `LARECOMP_WATCH_LIKE=<present>:<address>` | `LARECOMP_WATCH` only from that present on; only the first n writes; and every word in the heaps with that address's value at that present watched (the scan runs at the present, on the game's thread). Writes of up to 16 bytes that cover the word (SIMD vectors) now count |
| `LARECOMP_FPS_AT=<present>:<fps>,...` | changes the frame cap (30/60/120) at those presents, like the F12 menu |
| `LARECOMP_SET_AT="<present>:<key>=<value>;..."` | applies a `larecomp.ini` line at that present, the way the F12 menu changes an option with the game running (e.g. `1300:ssao_level=3;1400:aa=taa`; no spaces, to fit in a variable) |
| `fx_custom = 1` and the parameters in `larecomp.ini` | the effects' parameters by hand, like F12's Advanced tab: `ssao_radius`, `ssao_intensity`, `ssao_samples`, `ssao_temporal`, `contact_shadows`, `contact_steps`, `contact_strength`, `contact_length`, `contact_thickness`, `gi_intensity`, `gi_radius`, `gi_thickness`, `gi_rays`, `gi_steps`, `gi_div`, `gi_temporal` (without `fx_custom` the levels overwrite them; with it the levels only turn SSAO and GI on and off). Also with `LARECOMP_SET_AT` (e.g. `1300:fx_custom=1;1300:gi_div=4`) |
| `LARECOMP_MENU_PAGE=cfg/adv/<n>` | with `LARECOMP_MENU_AT`: opens the F12 settings (instead of the pause menu) on tab n - cfg the first (Graphics), adv the Advanced one |
| `LARECOMP_MENU_SMALL=1` | the F12 settings opened already in small mode (the one from Ctrl or the controller's top button, Y / X, hidden: half size, in the bottom-right corner, without darkening the game), for captures |
| `LARECOMP_UI2X_GENTLE=1` | "Make the 2x images" starts with waifu2x's gentle attempt (`-t 32 -j 1:1:1`), the one that comes after a rejected output |
| `LARECOMP_UI2X_GENERATE=1` | the start screen generates the interface's 2x images (`runtime/ui2x.c`, like the button) and exits: status 0 if it finished; the step by step goes to the log (`[ui2x]`) |
| `LARECOMP_TEXKEY_LOG=1` | logs the content key of each texture uploaded from the CPU (`[texkey] <64-bit key> <w>x<h> nvn <format> ...`: CRC-32 and Adler-32 of the deswizzled level 0, `ui2x_key`, the same as in `cache/ui2x.pak`). `tools/ui_texkeys.py <romfs.bin> <out.tsv> [<log>]` computes the same key for every interface texture in the game files and says which ones in the log match |
| `LARECOMP_FONT_SCALE=<1..4>` | forces the text scale (`runtime/hle/font_hires.c`) instead of the automatic one from the window height; `1` turns it off (to compare) |
| `LARECOMP_FONT_LOG=1` | logs the first 400 glyphs the game's font cache draws (code, size, metrics at 1x and at Nx, cell and line) and the size of the cache textures at Nx (`runtime/hle/font_hires.c`) |
| `LARECOMP_MV_YSIGN=-1` | (validation) flips the NDC y convention of the motion vectors; the right one in Let's Go is the default (+1) |
| Statistics every 2 s (`[vk] t=...`) | draws, passes, dispatches, uploads, `compile N (translate, spirv, pipelines, draws waited)` (programs and pipelines ready, the CPU time of each stage and how long the draws waited for them) and `[skip: ...]` with the draws skipped by reason. To measure a first visit, rename `cache/` before the test and put it back afterwards |
| `tools/perf_summary.py [log]` | a session summary: fps range, frames over 50 ms, skipped draws, compiles, audio underruns (default: `logs/jogo.log`) |
| `LARECOMP_FRAMETIME_CSV=<file>` | writes `present,dt_ms` for each of the game's presents (except the first), with monotonic time; the menu's extra in-between frame at 60 does not count. Use a path in `build/` |
| `tools/frametime_summary.py <csv> [--from-present N]` | mean, FPS, P95/P99 (nearest rank), maximum and the number of presents over 50 ms; filter the start to separate boot/loading from the world |
| `LARECOMP_VK_VALIDATION=1` + `VK_ADD_LAYER_PATH=C:\msys64\ucrt64\bin` | the Vulkan validation layer (it found the video textures' overflow) |
| `LARECOMP_VK_DEVLOST_TRACE=1` (+ `LARECOMP_SYNC_SUBMIT=1`) | the GPU's last operations before a device lost |
| `LARECOMP_SAVE_MSL=1` | saves each translated shader to `build/glsl/<addr>_{vs,fs}.glsl` |
| `LARECOMP_GLSL_CACHE=0` | without the on-disk cache of the GLSL translation (`cache/glsl.pak`, `runtime/nvn/maxwell/translate.c`): every program translated again (`[vk]` shows `glsl cache N read, M stored` when it is used). The pak belongs to one build (the time `translate.c` was compiled): from another build, unreadable or cut off midway, it starts over or is truncated at the first bad record (`[glsl]` in the log). To measure a cold translation, delete only `cache/glsl.pak` |
| `LARECOMP_DEBUG_FRAME=<frame>` | lists every draw of that frame (program, attribute formats, render targets and, per texture: size, format, flags, block height, address) |
| `LARECOMP_LOG_SKIN=1` (+ `LARECOMP_DEBUG_VSCB=1`) | details skinned draws: vertices, bone indices/weights, palette statistics |
| `LARECOMP_DUMP_SKIN=<n>` | writes the inputs of the n-th skinned draw to `build/skin/` |
| `LARECOMP_VK_UBO_DIRECT=1` | uniforms read straight from the game's memory on the GPU (experiment) |
| `LARECOMP_VK_EXACT_H2F=1` | half precision converted bit by bit in every stage, as before; without it only the vertex shaders do this and fragment/compute use `unpackHalf2x16` (HISTORY 63) |
| `LARECOMP_VK_COPY_VERTICES=1` | forces copying **all** vertices and indices, even the ones a compute writes (they may be stale); for normal use, `LARECOMP_VERTEX_READ` |
| `LARECOMP_NO_SCALE=1` | turns off internal resolution scaling |
| `LARECOMP_SCALE=<f>` | render height = 1080 x f (ignores the launcher). With `LARECOMP_FPS=0` it measures GPU headroom |
| `LARECOMP_SETTINGS=<file>` | another `larecomp.ini` (e.g. `smaa = 0` to compare without SMAA) |
| `LARECOMP_ANISO=<n>` | forced anisotropic filtering (default 16; 0 or 1 = the game's) |
| `LARECOMP_MIP_BIAS=<offset>` | (research) the mip bias of the game's textures with TAA / FSR 3.1: `log2(render / window)` + this offset (default −1 with FSR 3.1, −0.5 with TAA; 0 turns it off). Only CPU-loaded textures in 3D draws (`[post] mip bias` in the log) |
| `LARECOMP_DEBAND=0` | (comparison) without the last pass's debanding and one-8-bit-step dither (`deband.frag`) |
| `LARECOMP_CONTACT_STRENGTH=<0..1>` | (research) the strength of contact shadows (default 0.5). With `ssao_debug = 1` in the ini and SSAO off, the debug view shows only them |
| `LARECOMP_CONTACT_FLIP=1` | (research) flips the y of the sun direction in view space for contact shadows (the default is right: shadow under the feet) |
| `LARECOMP_SHADER_WAIT_MS=<ms>` | how long a frame may wait for shaders / pipelines being prepared before skipping draws (default 20; 0 = never) |
| `LARECOMP_HIDE_FIRST_FRAMES=<n>` | a black window for the first n presents (default 2: the opening's blue flash; 0 shows everything) |
| `LARECOMP_WINDOW_SHOT=<frame>` | writes the **window's** image to `build/window.png` (`LARECOMP_SHOT_AT` writes the game's image, before the window) |
| `LARECOMP_LOG_CLEARS=1` | each colour clear: frame, target, format, mask and the colour |
| `LARECOMP_DUMP_TEX_FMT=<NVN format>` | writes level 0 of the textures of that format, already untiled, to `build/tex/<addr>_<w>x<h>_f<fmt>_row<bytes>.bin` |
| `LARECOMP_VK_SKIN_ONEBONE=1` | skinned shaders use only the 1st bone (experiment X4; it was the stopgap before the fix) |
| `LARECOMP_VK_SKIN_IDENTITY=1` / `LARECOMP_VK_SKIN_IDX_X=1` / `LARECOMP_VK_SKIN_W=<expr>` | other experiments from [PLAN-3D.md](PLAN-3D.md) |
| `LARECOMP_DUMP_SKIN=1` + `LARECOMP_DUMP_SKIN_FRAME=<frame>` | writes the 1st skinned draw from that frame on to `build/skin/` |

### Shader harness on the CPU (`tools/skintest`)
Runs a translated vertex shader on the CPU with a draw's real data:
```
LARECOMP_SAVE_MSL=1 LARECOMP_DUMP_SKIN=400 ./build/lasrecomp.exe extracted --play
./.venv/Scripts/python tools/skintest/make_harness.py build/glsl/<vs>_vs.glsl build/skintest.cpp
clang++ -O1 -std=c++17 -w -o build/skintest.exe build/skintest.cpp && ./build/skintest.exe build/skin
```
The generated `.cpp` contains the game's shader: it stays in `build/` and never goes into git. If the folder has a
`gpu_pos.bin` (exported by `tools/rdc_draw.py`), each vertex also shows the position the GPU computed.

### RenderDoc (what the GPU really received)
RenderDoc 1.46 in `C:\Program Files\RenderDoc`. The runtime triggers the capture by itself when it runs inside it:
```
RENDERDOC=1 tools/repro.sh rdc 1310 LARECOMP_RENDERDOC_AT=1290 [LARECOMP_RENDERDOC_FRAMES=2]
```
This writes `build/rdc/capture_frameN.rdc` (4 frames in a row by default, because the game does not draw the whole scene
on every present) and `build/rdc-shaders.txt`, with each SPIR-V's hash and the shader's address in the game. To analyse,
use `qrenderdoc`'s Python. It hangs at startup if it finds VS Code's Python debugger in the user profile, so point
`USERPROFILE`/`HOME` at an empty folder **outside** `build/rdc` (`repro.sh` deletes that folder):
```
H="$(cygpath -w "$PWD/build/rdc-home")"
RDC_DIR=D:/projects/letsgo-recomp/build/rdc OUT=D:/projects/letsgo-recomp/build/rdc/skin.txt   USERPROFILE="$H" HOME="$H" "/c/Program Files/RenderDoc/qrenderdoc.exe" --python D:/projects/letsgo-recomp/tools/rdc_skin.py
RDC=<capture.rdc> EID=<event> OUT=<file.txt> USERPROFILE="$H" HOME="$H"   "/c/Program Files/RenderDoc/qrenderdoc.exe" --python D:/projects/letsgo-recomp/tools/rdc_draw.py
```
- `rdc_skin.py`: for each skinned draw, shows the shader, the NDC and `w` range and how many vertices leave the screen.
- `rdc_draw.py`: a draw vertex by vertex (`a11`, `a12`, `gl_Position`), separating the vertices with `w` off the median.
  Exports `build/rdc/draw_<eid>/` in the harness format (`verts.bin`, `cbN.bin`, `gpu_pos.bin`).

Do not turn on debug info in the shaders to capture: with thousands of shaders, the replay takes over 20 minutes just to
open.

### The game's functions: profile, comparison and hooks
- `LARECOMP_FNPROF=<from>:<to>` writes to `build/fnprof.txt` (or `LARECOMP_FNPROF_OUT`) the game's functions that ran in
  those frames: address, calls, order of first entry and the `lr` of that entry (runtime/fnprof.c).
  `LARECOMP_FNPROF_BT=<addr>[,...]` (+ `LARECOMP_FNPROF_BT_MAX=<n>`) prints the stack (functions `f_<addr>`) on the
  first entries of those functions.
- `tools/fncompare.py --base <profiles without the event> --event name=<profile>` lists what only the event executed;
  with two events, what is common and what belongs to each (example: docs/BATTLE-MODE.md).
- **Hooks** (runtime/fnhook.c): every generated function goes through `FN_ENTER`, which calls `rt_fnhook` while a hook
  is registered (`rt_register_fnhook(addr, fn)`; `fn` returns 1 to handle the call instead of the game;
  `rt_call_original` runs the original function from inside the hook). Changing behaviour does not require generating
  the DLL again.
- `LARECOMP_SCAN="<hex bytes>[@<frame>]"` (+ `LARECOMP_SCAN_BACK=<n>`; `LARECOMP_SCAN_LEN=<bytes>` logs more than 0x40
  bytes per hit, `LARECOMP_SCAN_NOPTR=1` skips the pointer search, which is slow): scans the guest's mapped memory for
  those bytes (e.g. a record's hash in little-endian) when the game reaches the frame (default 1300) and logs each hit,
  the next 0x40 bytes, `n` records of 0x40 before and the pointers to the base (runtime/hle/memscan.c, Windows only).
- `LARECOMP_HOOK_DUMP="<addr>:<args>[;...]"` (the full guest address, e.g. `700028ef70`; the offset in `main` alone
  does not trigger) logs, on the first `LARECOMP_HOOK_DUMP_MAX` (4) entries, x0..x7 and the arguments' memory:
  `x2:30` = 0x30 bytes at x2; `*x0:400` = 0x400 bytes at the pointer stored in x0.

### Cross-references in the game's code (`tools/xrefs.py`)
`cd tools && ../.venv/Scripts/python xrefs.py calls <addr>` (who calls the function containing the address),
`imm <value>` (instructions with that immediate) or `float <value>` (where the constant is and who loads it). The
disassembly of `main` is cached in `build/xrefs-main.pkl`. Calls through a vtable do not show: for those, the run-time
caller chain (the guest's frame pointers, `x29`) is the way.

### Playing while testing
`build/jogo/lasrecomp.exe` (double click) is the stable copy. `make jogo` (`tools/publicar_jogo.sh`, with the game
closed) copies the current build there after it is validated. That way, rebuilding and testing in `build/` does not run
into the executable locked by the open game.

## Video and audio
| Variable | Effect |
|---|---|
| `LARECOMP_AUDOUT_WAV=<prefix>` | writes each audio output to `<prefix>.<n>ch.raw` (s16, 48 kHz) |
| `LARECOMP_AUDOUT_MS=<ms>` | minimum queue of the audio output (default 60) |
| `LARECOMP_MOVIE_STATE=1` | state of the decoders' queues every 5 s |
| `LARECOMP_LOG_MOVIE_CALLERS=1` | who reads the video's frames (Buffer::Base, GetOutputBuffer) |
| `LARECOMP_MOVIE_MAX=<w>x<h>` | scales down videos larger than this |
| `LARECOMP_MOVIE_TEST_FILL=<byte>` | fills the video's frames with a value (test) |
| `LARECOMP_LOG_BUF2TEX=1` | log of the buffer → texture copies of the video planes |

To compare audio with the original:
`ffmpeg -i <video>.webm -vn -f s16le -ar 48000 -ac 2 ref.raw` and correlate with the recording (numpy in the `.venv`).
