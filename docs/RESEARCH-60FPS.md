# Research: how other ports reached 60 fps

_2026-10-15. **The prototype described below was removed from the runtime the same day** (too many visual errors: see
the end of the prototype section); the game stays at its original 30 fps. This page stays as a record. Context: Let's
Go advances its logic one step per frame; the time step exists, but only part of the game uses it ("Time map", at the
end of this page). Unlocking the cap leaves the game at double speed._

## The four techniques that exist

| Technique | How it works | Who uses it | Does it work for Let's Go? |
|---|---|---|---|
| **1. Just unlock the cap** | changes the present interval from 2 to 1 | Switch 60 fps mods (a `.pchtxt`/IPS patch on `nvnWindowSetPresentInterval`) | **No**: the logic doubles in speed. GBAtemp confirms that Let's Go's 60 fps mods have exactly this problem |
| **2. The engine already uses delta time** | the game computes physics from the frame's real time; the port only unlocks it and fixes bugs that appear at high fps | Sonic Unleashed Recompiled (the original game already had no fixed rate) | **No**: we measured that Let's Go does not use frame time |
| **3. Transform interpolation** (the most used in ports) | the logic stays at 30 Hz; for each extra frame, the renderer redraws the scene with the **matrices** (camera, objects, bones) halfway between the previous and current frame | Ship of Harkinian (Ocarina of Time), Zelda64Recomp and others with RT64, sm64ex | **Yes, this is the way**, adapted to our level (NVN instead of N64 display lists) |
| **4. Image-based frame generation** | creates the middle frame from two finished images (optical flow) | external frame generation programs, driver features | Works without touching the game, but the quality is worse (artifacts on the interface and text) and latency rises |

## How transform interpolation works in the ports

### Ship of Harkinian (decompiled Ocarina of Time source)
File `soh/soh/frame_interpolation.cpp`:
- Every logic frame, it **records a tree** of every matrix operation (translate, rotate, multiply, push/pop), indexed
  by the game object and by call order (`FrameInterpolation_StartRecord`, `FrameInterpolation_RecordOpenChild`).
- For an in-between frame, it **walks the new and the previous tree together** (`interpolate_branch`) and blends the
  values with a `step` factor (0.5 for 60 from 30). Angles take the shortest path; a difference that is too large is
  treated as a cut (no blending).
- Special cases: actor-relative matrices (avoiding the "paper" effect on 180° rotations), a camera that can ask "do not
  interpolate" on a scene cut, objects that appear/disappear (drawn without blending), ribbons and **skinned limbs**
  (keeping the previous and current vertex pose).
- It works because they have the source code: they call these functions at every place that builds a matrix.

### RT64 (Zelda64Recomp, static recompilation like ours)
- The renderer runs **two renderers**: one synchronized with the game (reading memory at the original pace) and another
  that **replays the recorded draw calls**, at a higher resolution and another rate, interpolating.
- To match what is the same object between two frames, the game's patches insert **extra commands** into the display
  list (`gEXMatrixGroup`, with an `id` and flags saying what to interpolate: position, rotation, scale, vertices,
  texture...). Without an `id`, there is an automatic mode based on order.
- Changing the fps **does not change the physics or the game's speed** (reports on Zelda64Recomp).

### sm64ex (Super Mario 64)
A 60 fps patch applied to the decompiled code: logic at 30 Hz, animations and objects interpolated in the rendering
path.

## What this would mean in our runtime

We have neither the source code (like SoH) nor N64 display lists (like RT64). But we have something similar to RT64:
**every NVN command of each frame goes through the runtime** (`runtime/nvn/cmdbuf.c`, `vulkan/exec.c`). A prototype:

1. **Record the frame**: keep frame N's list of draws (program, buffers, copies of the uniform buffers).
2. **Match draws between N−1 and N**: by order within the pass, program and vertex buffer address (like RT64's automatic
   mode).
3. **In-between frame**: replay N's draws with **blended uniform buffers** between N−1 and N:
   - `cb3` (world and camera) and `cb4` (bone palette) are matrices: blendable;
   - camera cuts and new/vanished objects: no blending (as in SoH).
4. Present the in-between frame between the two real frames: it costs **one frame of latency** (~33 ms).

Risks and uncertainties:
- Draw matching may fail in scenes with many objects, particles and lists that change order.
- The interface (menus, text) and full-screen effects should generally not be interpolated.
- Data computed by the GPU (compute) and animated textures do not interpolate this way.
- Interpolating matrices with perspective or scale needs decomposition (RT64 has a `DECOMPOSE` mode).
- It is large, exploratory work: weeks, not days. But it is the same family of technique that the successful ports use.

## Prototype (2026-10-15): 60 FPS in the launcher / `LARECOMP_INTERP=1`

Implemented in `runtime/nvn/vulkan/exec.c` (section "frame interpolation") and `device.c` (`backend_present`):
- **Recording**: each frame's command lists (with a hash of the content), the execution state at the start of the
  frame and a copy of each uniform buffer (cbuf 3+) of the vertex and fragment stages. The key of each copy: stage,
  binding, program, vertex buffer 0, the draw's parameters and the occurrence of that key in the frame.
- **Replay** at frame N's present: the same lists from the initial state, skipping whatever writes to the game's memory
  (compute, copies to buffers and from buffers to textures, inline uniform updates, syncs, counters). Each uniform is
  the word-by-word blend of N−1's and N's copies, only for normal floats and without a large jump (camera cut, scrolling
  textures); the rest, and draws without a pair in the previous frame, keep N's value.
- **Presentation**: keeps N's image in a copy, shows the in-between frame and, half a period later, N.
- **Safety**: no in-between frame when some list changed since execution (the game reused the memory) or when the game
  destroyed textures, pools or programs in the frame (the recorded state could point to them).

Results (Pallet Town, `tools/repro.sh` walking with the stick):
- **It works**: between frames 1329 and 1330 the scenery moves 12 px; the in-between frame is **6 px** from each
  (measured by aligning the images). The character and Eevee are also halfway; menus appear correct.
- **Stable**: 2,000 frames without error, no Vulkan validation warnings; an in-between frame in ~99% of frames; the logic
  stays at 30 fps (the GPU cost doubles: each frame is drawn twice).
- **Known defects**: a thin white line near a door in the in-between frame (probably two pieces of geometry, one with a
  pair and one without); an extra half frame (~17 ms) of latency.
- **Not tested**: battles, cutscenes, effects with particles and compute, shadows of objects that appear/disappear.

To test: choose 60 fps in the launcher (`larecomp.ini`: `fps = 60`), or `LARECOMP_INTERP=1` +
`LARECOMP_WINDOW_SHOT=<frame>` (writes `build/window_mid.png`, the in-between frame, and `build/window.png`, the frame).
`LARECOMP_SHOT_AT` writes the game's image after the replay, i.e. the in-between frame.

### Why it was removed
Testing on the route, in the grass, in the town and in the capture (recording the in-between frame and its neighbours,
frame by frame) the errors came one after another: identical objects (flower beds, Pidgeys) paired with the wrong
neighbour became ghosts; capture menus blank; skinned models stretched; a flash over the Poké Ball. Each had a fix
(one-to-one pairing by content, 3D draws only, no bone palettes, a relative threshold), but another case always
appeared - without the per-object markings RT64 receives from the game's patches, matching between frames is a guess.

## Investigation of 2026-10-16: identifying each object through the game itself

What the prototype lacked was knowing **which object is which** between two frames. Found with
`LARECOMP_DRAW_CHAINS` and `LARECOMP_HOOK_DUMP` (+ `_FRAMES`), in Viridian, standing still and walking (frames
1450-1460):

- Per frame the game records 117 command lists, makes ~407 `nvnCommandBufferCallCommands` (prebuilt lists) and only ~37
  direct draws: almost every object is drawn by calling a list recorded earlier.
- 356 of those calls come from **`f_70006237b0`**, called per item by the loop in `f_70006453a0`
  (`... f_7000644b50 → f_70006453a0 → f_70006237b0 → f_70005e3000 → CallCommands`). It is called 22 times per frame,
  once per object, with the **object in x0**.
- The pointer in x0 is **stable**: the same 22 objects across 10 consecutive frames while walking, none repeated within
  a frame.
- The **order changes** every frame (only 2 to 14 of the 22 stay in the same position): that is why pairing by order
  produced ghosts.
- A second path, `f_7000641190` (via `f_7000642990`), draws 7 objects, each in two passes per frame (shadow/depth and
  colour): also stable; key = object + pass.

Conclusion: with hooks on these functions, each list call can carry the identity of the object the game is drawing, like
RT64's `gEXMatrixGroup`. The interpolation prototype (commit `9f2f5e5`, removed in `d72ab33`) can come back pairing by
object instead of by order; draws without an object (interface, screen effects) keep the current frame's values.

## Sources
- Ship of Harkinian, interpolation: [frame_interpolation.cpp](https://github.com/HarbourMasters/Shipwright/blob/develop/soh/soh/frame_interpolation.cpp)
- RT64: [repository](https://github.com/rt64/rt64) and [extended commands (rt64_extended_gbi.h)](https://github.com/rt64/rt64/blob/main/include/rt64_extended_gbi.h)
- Zelda64Recomp and high frame rates: [DSOGaming](https://www.dsogaming.com/news/the-legend-of-zelda-majoras-mask-just-got-an-unofficial-pc-port-with-support-for-high-framerates-widescreen-ultrawide-gyro-aim-autosaves-and-low-input-lag/), [Digital Foundry via Nintendo Life](https://www.nintendolife.com/news/2024/05/video-digital-foundry-takes-a-look-at-zelda-64-recompiled-majoras-mask)
- Sonic Unleashed Recompiled: [README](https://github.com/hedge-dev/UnleashedRecomp/blob/main/README.md) (section "High Frame Rate Glitches")
- Switch 60 fps mods (the present interval method): [GBAtemp tutorial](https://gbatemp.net/threads/how-to-make-60fps-ips-patch-for-nintendo-switch-game-ghidra-tutorial.625675/)
- Let's Go and 60 fps (double speed): [GBAtemp](https://gbatemp.net/threads/request-lets-go-eevee-and-swsh-1-3-1-60-fps-mod.581515/)
- sm64ex: [Game Tech Wiki](https://emulation.gametechwiki.com/index.php/Super_Mario_64_Port), [VGC](https://videogameschronicle.com/news/mario-64s-pc-port-has-been-modded-to-run-at-60fps)

## The community 60 fps mod (Fl4sh9174), decoded — 2026-10-16

Source: [Switch-Emulator-Ultrawide-FPS-Mods](https://github.com/Fl4sh9174/Switch-Emulator-Ultrawide-FPS-Mods) (commit
`91db608`), packages "Pokemon Let's Go Eevee" and "Pokémon Let's Go, Pikachu!" (cloned into `reference/fl4sh-mods`,
outside git).

| Package | Version | Patch Build ID | Writes (`@flag offset_shift 0x100`: address = offset in `main`) |
|---|---|---|---|
| Eevee, 60 FPS | **1.0.2** | `5831EC64D6B696FD69E69505821B97B1` | `005e78b8 0A000014` (= `b #+0x28`); `00f7eec0 2b50fe00` (u32 = 16,666,667) |
| Eevee, 120 FPS | 1.0.2 | same | the same code write; `00f7eec0 e655a300` (u32 = 10,704,358, ≈93 Hz, **not** 8.33 ms) |
| Pikachu, 60 FPS | 1.0.2 | `C208DB6A4EF4361F28B8402BE0F7CD9A` | the **same** two addresses and values as Eevee |

Our files are **v1.0.0** (Build ID `0a3f0d21e67dad80bb39beeaedbb0bab`): the Build IDs do not match, so nothing holds by
assumption.

- **Data write (`main+0xf7eec0`): confirmed on 1.0.0.** It is `G[1]` of the frame duration table (`G[0]`=16,666,667,
  `G[1]`=33,333,334, `G[2]`=50,000,000 ... at `main+0xf7eeb8`). The mod swaps 33.33 ms for 16.67 ms. It is the same as
  what `accessor_hook` in `runtime/hle/fps60.c` does, except that there the swap only applies when the world reads
  `G[1]`; in the mod it applies to every reader, which is why menu, battle and capture speed up (they have integer frame
  counters, see below).
- **Code write (`main+0x5e78b8`, `b +0x28`): NOT mapped.** On 1.0.0 that address is a `blr x8` in the middle of
  `f_70005e7890` (an NVN pointer call, slot `0x1603b88`); replacing it with `b +0x28` would skip loading `x21` and write
  to `[x21+0x208]` with the caller's `x21`, which is not the intended patch. In other words, 1.0.2's code is shifted and
  the original instruction can only be identified with 1.0.2's `main`, which we do not have. The neighbourhood is the
  wrapper of `nvnWindowGetPresentInterval/SetPresentInterval` (`f_70005e79c0`, slots `0xc38`/`0xc40`), so the
  hypothesis is that the patch changes the present interval (from 2 to 1), but **that is a hypothesis, not measured**.
- The 120 FPS one uses `G[1]`=10.7 ms, which is not 1/120: the effect is not an "exact rate", and the relationship is not
  explained.
- Eevee and Pikachu 1.0.2 use the same addresses in both patches, but that was only read from the files; we did not test
  Pikachu.

## Time map (2026-10-16)

Corrects the "there is no global time step" of the header and of PROGRESS: there is a reference, but only part of the
game uses it.

**Who reads the `G` table** (`main+0xf7eeb8`, via the pointer `0x70015fb438`; surveyed by `adrp`+`ldr` across all of
`main`, 9 instructions):

| Function | What it does with `G` | Runs in the world? |
|---|---|---|
| `f_7000039600` (accessor) | `step[i] = G[idx]` in the timers object (called with `i = 1`, `idx = 1`, once per world update, from `0x70000393bc`) | yes, 1 per frame |
| `f_7000663660`, `f_7000664cd0` | `step / (G[idx] - 1)` = frames to advance (animations) | yes |
| `f_700067be50` | `step / (G[0] - 1)` × a per-frame speed | yes, 2 per frame |
| `f_7000029d30` (end of frame) | `step0 / (G[0] - 1)`, clamped to 1..5: statistics only (the value goes to `f_70000358b0`, which does not use it) | yes |
| `f_7000038ae0` | copies `G[1]` into an object's fields on creation | not measured |
| `f_70000393e0` | `step / (G[4] - 1)` | not called in the world |
| `f_7000039520` | compares a time with `G[3]`, `G[2]`, `G[1]` (picks a range) | not called in the world |
| `f_700016d840` | `amount × G[1]` (frames in nanoseconds) | not called in the world |

**The timers object** (on the main thread's stack, `0x723ffff450` in the measured runs): 16-byte entries; the getter
`f_70000395f0(obj, i)` returns `obj + 8 + 16·i` and the step sits at `+8` of that. Measured (`LARECOMP_ELAPSED_LOG`,
`LARECOMP_HOOK_DUMP` on the accessor and on the setter `f_7000039620`):
- step 1: 33,333,334 ns at 30 fps; with `LARECOMP_FPS60=1` in the world, 16,666,667 ns (the accessor hook). Rewritten
  on every world update;
- step 0: 33,333,334 ns always (including in 60 mode), written outside the accessor.
- The animations' "elapsed time" **is not measured**: it is this step. That is why the game neither speeds up nor slows
  down with load, and swapping `G[1]` only in the accessor changes exactly those who use step 1.

**Who reads each step** (`LARECOMP_TIMER_USERS`, getter calls by return address, 30 frames in the world and 90 in the
capture): the same readers in both cases.
- Use the **value** of step 1: `0x70005ed1e8`/`0x70005ed908` (16 per frame), `0x7000664d18`, `0x70006636a8`,
  `0x700067bf20`, `0x70006875e4`, `0x7000655634`.
- Use the step only as "update or not" (`> 0`): `0x700002333c` (~2,300 per frame, almost all on step 0),
  `0x700061640c` and `0x7000616494` (both steps, depending on the object).
- Step 0 with its value: only `0x7000029e70` (the end-of-frame statistic).

**Consequences**
- The world at 60 (`accessor` with `G[1]` = 16.7 ms): whoever converts time to frames through step 1 advances half a
  frame per update, at the right speed. Confirmed in game.
- What advances **per update**, without looking at the step, doubles in speed at 60. In the capture and the battle that
  includes the scene's timelines (the counters found by tracing writes: `0x7000b88340`, `0x7000b6acc8`,
  `0x70002d2a44`), the arc and the ball. Dividing those three counters (mode 2, `rt_scene_tick`) left the Pokémon at the
  right speed, according to the in-game test, but the arc and the throw stayed fast: **there is more per-frame logic
  those counters do not cover**. That is why the sustainable option for these scenes is to keep the logic at 30 and
  present at 60 (interpolating only safe graphics state).
- Hypotheses not yet verified: what writes step 0; whether `f_70000393e0`/`f_7000039520`/`f_700016d840` run in battle
  or in other scenes; whether any value reader of step 1 depends on it being exactly 33.3 ms.

**Tools** (runtime/hle/fps60.c, docs/DEBUGGING.md): `LARECOMP_ELAPSED_LOG="<function>:<step>,..."` (+
`LARECOMP_TIME_PROBE_FRAMES`), `LARECOMP_TIMER_USERS=<from>-<to>`, `LARECOMP_TIME_PROBE`, `tools/teste60.sh`.
Careful: `fnhook` accepts **one hook per address** (the last registered wins); two probes on the same address cancel
each other (this invalidated a mode 2 test with `LARECOMP_SHOT_REL`, already fixed).

## The architecture adopted and validation of interpolation in scenes (2026-10-16)

- **World and menus**: native 60 Hz (step 1 of 16.7 ms through the accessor, "Time map").
- **Battle and capture**: logic at 30 Hz, like the game; presentation at 60 with the in-between frame
  (`LARECOMP_FPS60=1`). The interpolation only blends 3D draws with an identified object
  (`f_70006237b0`/`f_7000641190`), into a target with depth and with the depth test on; interface, transitions and
  effects without an object keep the current frame (they move at 30). The blend is per vec4, all or nothing.
- Mode 2 (divided counters) stays research only: the battle remains ~2× fast (`tools/teste60.sh batalha 2`).

Validation (`tools/teste60.sh <scene> 1 LARECOMP_WINDOW_SHOTS_REL=1 LARECOMP_WINDOW_SHOTS=...` and
`tools/interp_metrics.py`): the main metric is the fraction of the in-between frame's pixels that exist in neither of
the two neighbouring frames within a 4 px radius (what the interpolation invented). Battle: 42 of 47 frames below 0.5%;
the others are a transition cut and fast camera turns, coherent in the image. Capture: no frame above 0.5%.
Pending: the player confirming at real speed; the interface and effects without an object stay at 30.

## Decision (2026-10-17): no interpolation

Tested in game after the fixes above, interpolation in battles and captures still had defects visible to the player.
It was taken out of 60 mode: `LARECOMP_FPS60=1` leaves the world, menus and Pokédex at native 60 (the accessor's step 1)
and battles and captures at 30, like the original game, with no in-between frame. The interpolation code stays for
research only (`LARECOMP_INTERP=1`); choosing 60 fps in the launcher no longer turns it on.

## Walking speed at 60 and 120 fps (2026-10-19, Pikachu 1.0.0)

The world at 60 / 120 did not walk at the right speed: the player went at ~85 % / ~53 % of the 30 fps speed.

**Measurement** (`tools/walk_speed.sh <name> <fps>`): a dry run, walking down in Viridian 5 s of game time after the
world starts (present 1350 + 5·fps: with the area's name on screen the d-pad is ignored) and the position of the camera,
which follows the player, every frame (`LARECOMP_CAM_LOG=1`, `exec.c`: −Rᵀt of the scene block's view matrix). Steady
speed: **391 cm/s at 30, 331 at 60, 211 at 120**, or per update 13.04 / 5.52 / 1.76 cm. That is exactly
`450.8 cm/s × step − 2.0 cm`: one part proportional to time and one part **fixed per update**.

**Where** (`LARECOMP_WATCH_LIKE=<present>:<address>` in `memwatch.c`: at the given present, every word in the heaps with
the same value as the player's position; the writes to each, with the stack, in order). Per update, at the player's
position (the object of `f_70005ed120`, +0xb0 x/y/z):
1. `f_700021b6f0` adds `rotate(orientation +0xa0, global vector × s16)`: **−2 cm** running forward. `s16` is one of the
   parameters +0x70 / +0x74 / +0x78 of the movement component (its x0, only one per frame: the player's), chosen by the
   d-pad's state (3 states by thresholds; 0 in state 1). Tuned for a 33.3 ms update.
2. `f_70005ed550` (from `f_70005ed120`, the animation) adds the animation root's displacement: proportional to time.
3. `f_7000213c50` rewrites the same value.

The same `f_700021b6f0` turns the player towards the d-pad with `f_700020b7e0` (quaternion slerp) and **t = 0.5 per
update**: at 60 / 120 fps, the turn was 2× / 4× faster.

**Fix** (`runtime/hle/fps60.c`, "the player's walking"): while `f_700021b6f0` runs in the world at 60 / 120 fps, the
three parameters are multiplied by step / 33.3 ms and the t of the slerp called inside it becomes
1 − (1 − t)^(step / 33.3 ms). Functions found from the code (a signature near the Pikachu 1.0.0 address; Eevee's is a
few instructions away). Result: **391 cm/s at 30, 60 and 120 fps**; 2 s of running: 754 / 736 / 742 cm. In a 90° turn
a ~0.05 s difference remains at the start (at 30 fps each update turns 45° at once and already moves 13 cm in the new
direction). `LARECOMP_FPS60_NOWALKFIX=1` turns the fix off, for comparison.

**How it was found** (for the next wrong speed): `LARECOMP_STEP_SCALE=<fn>:<factor>` (step 1 multiplied during a
function: only `f_70005ed120` changed the speed), `LARECOMP_FARG_SCALE=<fn>:<factor>` (the first float argument:
`f_70005febd0`, the animation's time advance, is the lever, and the speed as a function of it gave the line above),
`LARECOMP_FIND_MOVER=<present>` (inside `f_70005ed120`'s objects, the float triples that move 1–20 cm per update: the
player's position) and `LARECOMP_WATCH_LIKE` above. Disassembly: `tools/disasm.py` (with the game's `main` in
`extracted/exefs`).

## A free multiplier by replay (2026-10-19, Pikachu 1.0.0)

Question: generate 3x / 4x like Lossless Scaling, on any GPU, without depending on FSR (only 1 interpolated frame on
Vulkan) or DLSS (multi-frame only on the RTX 50). The path explored: this page's replay interpolation, with k − 1
in-between images per present instead of one.

- **Code**: `vk_interp_render` became `vk_interp_begin` (the checks and the copy of N) + `vk_interp_replay(t)` (the
  replay at point t, callable several times) + `vk_interp_end` (the recording moves on to the next frame after all of
  them). `backend_present` (`device.c`) draws k images, the j-th replayed just before it appears, at j/k of the period
  after N−1. The in-between images' camera (`mv_replay_camera`) accepts N's k − 1 replays, not only the first.
  `LARECOMP_INTERP=1 LARECOMP_INTERP_MULT=<k>` turns it on (DEBUGGING.md).
- **The defect that took interpolation out of the world**: flower beds and grass are the same mesh drawn dozens of times
  without a game object, matched between frames by draw order; when the camera moves and one of them leaves the frame,
  the order shifts by one and each blends with its neighbour (in the Pallet Town frame where a bush leaves, the
  in-between image almost without the flower bed). Now each draw picks, on the first cbuf, the previous frame's
  occurrence with the closest copy (`ip_pick`, the same idea as the motion vectors' `mvo_pick`) and uses it on the other
  cbufs. Invented pixels (outside both neighbours within 4 px, top-left half): 1/4 and 3/4 from 0.11–0.21 % to
  0.03–0.05 %, 1/2 from 0.79–0.87 % to 0.65–0.69 %; the flower bed stays whole.
- **Position**: base 30, k = 4, camera moving down: the ground in the images moves 0 / 1.00 / 2.12 / 3.09 / 4.05 px
  (steps of 1/4). Base 60 (native 60 mode), k = 4: 0.47 / 0.99 / 1.72 / 2.08 px (small displacements, a noisy
  measurement).
- **Cost**: ~2.6–3 ms per in-between image on the game's thread in Pallet Town (the same with FSR 3.1, SSAO and high GI);
  interpolation turns off the render thread.
- **Pacing, the current limit**: the images come from the game's own thread, waiting period/k between them, and the last
  sits at (k − 1)/k of the period. Base 30 with k = 4 (120 images/s) and base 60 with k = 2 (120) keep the game at the
  right speed; base 60 with k = 4 (240, a 240 Hz monitor in mailbox) drops the game to ~33 fps: ~4 ms are left for the
  next frame. For high multipliers the presentation must leave the game's thread (the k − 1 images ready in copies and a
  thread that presents them on time, as FSR 3's swapchain does).
- **Still to solve**: the interface, particles and unpaired objects stay at N (they move at the base rate); with TAA /
  FSR 3 the images are rendered out of order in time (N, then the ones before it), the history goes back and forth; an
  extra base frame of latency; the render thread turned off.

### On-time presentation and frame generation in the menu (2026-10-19)

- **Off the game's thread**: the k − 1 in-between images are rendered and kept all at once at N's present (each with its
  own post-processing, while the depth, the vectors and the jitter are its own: `vk_interp_keep`, `IpKeep`); the first
  appears right away and the others wait in a queue (`device.c` `vk_pending_*`) that the render thread presents on time,
  between the next frame's jobs or waiting with a deadline (`renderthread.c` `wait_work`). Without the render thread,
  the wait stays on the game's thread. Everything must be rendered at the present: recording the next frame clears
  N−1's copies.
- **The race**: with the render thread the game went up to two presents ahead and rewrote, for N+2, the memory of the
  lists that N's present was replaying (an access to 0 in `exec_list`, on the first attempt with k = 8). With
  interpolation on, the game goes one present ahead (`rt_present`).
- **F12 frame generation** (`frame_gen = 2 / 3 / 4`) uses this interpolation; FSR 3.1's and AMD's swapchain were
  removed. k = frame_gen × fps / base, the base being the world's rate (fps) or the game's own 30, whichever is closer
  to the measured frame pace (menus and battles at 30 in 60 mode get twice the images). Proportional to the period (the
  first version), without the render thread the waits lengthened the period, k rose and the game fell to ~26 fps.
- **Measurements at real speed** (Pallet Town, RTX 5070 Ti, 240 Hz monitor, mailbox): base 30 × 2 / 3 / 4 = 60 / 90 /
  120 images per second; base 60 × 4 = 240 (also with FSR 3.1, SSAO and high GI), with the game at 60; the X menu in 60
  mode with 4x: 240 (k = 8) with the game at 30; without generation, 60 mode as before (menus with the in-between image:
  60). Positions with k = 4 through the queue: 0 / 0.99 / 2.09 / 3.08 / 4.04 px. 9000 frames in turbo (26,101 replays),
  walking and opening the menu, with FSR 3.1 and SSAO: no failures.
- **Pending**: the interface and particles at the base rate; TAA / FSR 3.1 with the images out of order in time; battles
  and captures with generation on not verified after pairing by content; Eevee not tested (the interpolation does not
  depend on addresses).

### Side images and 4K (2026-10-19)

- **Reported problem**: at 4K performance dropped and the image "shook in blocks". In the player's logs: native FSR 3.1
  (3840x2160), medium SSAO, high GI; with 2x the game fell from 60 to ~26-35 fps.
- **Feedback in k**: k came from the measured period; a frame the GPU did not finish in time arrived later, got more
  images (4 instead of 2) and fell further behind. Now k = frame_gen × fps × `fps60_period_ns()` (the pace 60 mode
  intends: the world at 60 / 120, menus, battles and the start at 30), without the measured period.
- **Side images**: rendered after N, but before it in time, the in-between images counted as frames of their own
  (`fx_frame`) and pulled every history backwards and forwards: the GI accumulation (half resolution, 4 rays) and the
  SSAO's flickered in patches, TAA and FSR 3.1 received the past after the future, and the jitter sequence skipped
  phases (at 2x, half of FSR's eight). Now the in-between images read N's state and do not change it: N's camera saved
  and restored around each of them (`ip_cam_save` / `ip_cam_restore`, their previous frame is N); their per-object
  vectors do not record and use N's record (`mvo_prev_frame`); SSAO / GI = N's result moved by their vectors
  (`reproject.frag`, post images 28 / 29), without recomputation; TAA reads N's history and writes separately (post
  image 27); with FSR 3.1 they are resolved against FSR's output for N like a TAA (`side_resolve.frag`, post image 30) -
  a second FSR context for them was tried and dropped: their vectors are relative to N, not to the previous in-between
  image that context had in its history, and they came out compressed backwards. The real frames chain by the present
  count (`vp_real`, `CamReal.real`, the SSAO / GI / TAA histories, the vectors' record), and the jitter has one sequence
  for the real frames and another for the in-between images.
- **Measurements**: camera still, 4K, FSR 3.1, ground only: real → in-between → real 0.49 / 0.20 before (back and forth),
  0.35 / 0.35 now, like real → real (0.31). Camera moving: the in-between images follow the movement in all four modes
  (no AA, SMAA, TAA, FSR). 4K at real speed (world at 60, medium SSAO, high GI): native FSR 2x 60 fps / 120 images
  (before ~30 / 120), native 3x ~48 / ~145, Quality 3x 60 / 180, Quality 4x ~55 / ~220. One frame with one in-between
  image at 4K: 9.5 ms of GPU against 6.7 without it. 9000 frames in turbo with FSR and with TAA (26,101 replays each): no
  failures.
- **Tests**: the player's save changed (they kept playing: Route 1); the scripts give other scenes at the same frames and
  the earlier measurements (Pallet Town) do not compare with the current ones.
