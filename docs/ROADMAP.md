# Roadmap to a mature native port

_2026-10-17. An inventory of the code and the current documentation. This file is a verifiable backlog, not a claim that every item is a bug. Each item's state should be updated with links to reproductions, logs, captures or tests before a release._

## Scope and priority

The main target is **Eevee and Pikachu 1.0.0 on Windows**, with faithful gameplay at 30 fps. The launcher also accepts 1.0.1/1.0.2, but the [README](../README.md) says those versions were not tested locally and that the address-based options only apply to 1.0.0. Announcing support for the updates requires testing them; otherwise present them as unverified compatibility. The 60 mode and wild battles stay **experimental** until they meet their own criteria. Online features, the Poké Ball Plus and co-op need an explicit scope decision; a mature product may state that it does not offer them, as long as they neither hang nor confuse the user.

Priorities: **P0** save loss, a serious reproducible failure or widespread corruption; **P1** blocks the stable version's quality; **P2** improves robustness, performance or fidelity after the gates; **P3** optional expansion. There is no confirmed P0 in this inventory. If one appears, it interrupts the queue.

Each item carries its type: **observed** (already reproduced), **validation** (missing coverage), **hypothesis** (the code suggests a risk, no failure measured yet) or **decision** (product scope).

## Phase 1 — Prove the whole game and protect the data

This phase is the critical path. Before raising quality or fps, we need to know where the stable version fails.

| ID | Pri. / type | Work | Done when |
|---|---|---|---|
| J01 | P1 / validation | Play a full campaign of **Eevee 1.0.0**, from a new game to the credits, with saves at fixed points. Include gyms, caves, cities, events, battles, captures, evolution, the box and returning to earlier areas. The README only records tests up to Viridian City. | A per-chapter script with build, hardware, test save, failures and result; no blocked progression or reproducible crash. |
| J02 | P1 / validation | Repeat a campaign of its own for **Pikachu 1.0.0**, past the name screen; test playing with Pikachu and the exclusives. Do not validate parity only with a save copied from Eevee. | The same script and criteria as J01, including the specific differences. |
| J03 | P1 / validation | Exercise save/load at checkpoints, normal exit, restart, multiple saves and a write error / no space. Audit `runtime/services/fs.c` and the replacement/backup policy before changing any format. | The original save preserved; a test copy opens after each case; write failures reported without losing a valid save. |
| J04 | P1 / validation | Build a regression matrix for boot, menus, character creation, world, NPCs, transitions, battle, capture, save, video and audio, in **both** games. Use `tools/repro.sh` with isolated test folders and complete it with a manual checklist. | Every relevant fix runs the affected scenarios; logs and images tied to the build; no test touches the player's save. |
| J05 | P1 / validation | Test the **1.0.1/1.0.2** updates of both games, or reduce the public promise of support until there is evidence. Check the launcher, generator, HLE, saves and the features without fixed addresses. | A per-title/build table with the features tested and disabled; README and launcher agree. |
| J06 | P1 / validation | Rehearse the release zip on a clean Windows, without MSYS2/Python/Zig on the PATH: extraction, choosing one's own files, generation, close/reopen, errors and a version update. Repeat for Eevee/Pikachu. | A reproducible package, without game files or keys, and the install script completed on both titles. |
| J07 | P1 / validation | Test Windows 10/11 and NVIDIA, AMD and Intel GPUs (compatible dedicated and integrated), including different drivers, focus changes, resize, fullscreen, suspend/resume and device lost. | A published matrix with driver version, resolution, mode, validation logs and limitations. Do not announce an untested combination. |
| J08 | P1 / validation | Test a long session with audio on, the opening video, area changes, battle, capture and repeated save/load. Measure RAM/VRAM, handles, Vulkan objects and underruns. | No unexplained continuous growth, no noticeable desync and no reproducible drop; measurements and duration recorded. |

## Phase 2 — Fix visible defects and harden the runtime

| ID | Pri. / type | Work | Done when |
|---|---|---|---|
| R01 | P1 / observed | Solve the **special Pokémon's aura that vanishes for one frame**, also in the release at 30 fps (`docs/PROGRESS.md`). Use `LARECOMP_COUNT_TEX`, `LARECOMP_COUNT_FS`, `LARECOMP_TRACE_COUNT` and a save with an aura Pokémon; avoid using F9 as proof, since it changes the first recorded frame. | The cause located in a draw/state/effect, a minimal fix and a frame-by-frame comparison on Eevee/Pikachu. |
| R02 | P1 / observed | Reduce objects that appear late on the first visit because of a new shader/pipeline. Separate translation, SPIR-V, pipeline creation and the draw's wait; investigate preparing ahead per area and persisting the cache. | The same route with a cold/warm cache, a count of skipped draws and P95/P99 before/after, with no loading or RAM regression. A pipeline cache is recommended practice in the [Khronos documentation](https://docs.vulkan.org/guide/latest/pipeline_cache.html), but the current mechanism must be measured in the game. |
| R03 | P1 / hypothesis | Inventory `UNIMPLEMENTED` and success replies without an object in `runtime/dispatch.c`/`ipc.c`. Check in the SDK which `nn::Result` and payload each call really expects; keep the offline stubs that avoid loops/crashes. | Zero false successes on exercised paths; the correct error/object shown per call and per scenario test. |
| R04 | P1 / validation | Run Vulkan validation, synchronization validation and RenderDoc captures in representative scenes; investigate the known case of an RGBA8 texture sampled as a shadow (`docs/HISTORY.md`). | No error attributable to the runtime on the supported paths, or a specific documented exception with measured impact. [Khronos](https://docs.vulkan.org/guide/latest/development_tools.html) describes these layers as tools for access conflicts and shader errors. |
| R05 | P1 / validation | Check the 3D outside Pallet Town: skinned models in battle, large Pokémon, several cities, caves, shadows, particles and effects. | A set of reference captures at 720p/1080p/1440p/4K and an inspection of geometry, depth, viewport, scissor and UI in both games. |
| R06 | P2 / hypothesis | Measure concurrent readers of `G[1]` while `accessor_hook` changes it temporarily (`runtime/hle/fps60.c`). If there is a race, move the change to the timers object or another validated local point. | A list of readers/threads and a concurrency test; no temporary value exposed to unintended scenes/threads. |
| R07 | P2 / hypothesis | Audit the growth of `Prog`/`Pipe`, descriptor pools, textures, command buffers and the view cache in long sessions. `exec.c` keeps certain objects to preserve pointer identity. | Object and byte counters stabilize on a repeated route; any new release of objects goes through a lifetime test with validation. |
| R08 | P2 / validation | Check the semantics of the recompiled code: indirect branches/jump tables, registers, exclusives, barriers, FPCR/FPSR, rounding, NaN, NEON/AVX2, alignment and stores. Prioritize instructions in hot functions or tied to real bugs. | A differential corpus with legitimate ARM64 reference results and per-function traces; no tuning based only on an isolated microbenchmark. |
| R09 | P2 / validation | Confirm return codes, timeout and cancellation of the kernel, filesystem, input, offline network, audio and video services. The history shows several cases where the SDK's semantics differed from LASRecomp's. | Cases reproduced against the SDK/disassembly, timeout and failure tests, no deadlocks on reopen/reboot. |
| R10 | P2 / decision | Handle offline actions with no useful way out (e.g. "Connecting..." in Mystery Gift): leaving with B, a clear message or marking it unavailable in the launcher, without faking an online service. | No supported flow gets stuck; documentation and interface reflect the real behaviour. |

## Phase 3 — Performance, image and 60 fps, with measurements

| ID | Pri. / type | Work | Done when |
|---|---|---|---|
| D01 | P1 / validation | Define reference hardware and fixed routes per scene. Record frame times per present (`LARECOMP_FRAMETIME_CSV`), CPU per thread, GPU timestamps, RAM/VRAM, shader compiles, skipped draws and audio; separate cold/warm cache and boot/gameplay. | Reproducible 30 fps baselines on Eevee/Pikachu and at least one GPU from each supported vendor, with mean/P95/P99 and the full configuration. |
| D02 | P2 / hypothesis | Use a CPU profile to choose recompiled functions and runtime costs (`LARECOMP_FNPROF`, the CPU sampler); evaluate dispatch, uniform/vertex copies, mutexes, allocations and hot loops. Only then try flags, LTO or PGO. | An improvement before/after on the same route and hardware, with no functional divergence; build cost and compatibility recorded. |
| D03 | P2 / hypothesis | Measure `vk_full_barrier`, submits, descriptor sets, staging, uploads, framebuffer copies and waits in `runtime/nvn/vulkan/exec.c`. Reduce barriers only with known resource dependencies. | GPU timestamps and sync validation before/after, no artifacts; the [Khronos synchronization guide](https://docs.vulkan.org/guide/latest/synchronization.html) warns of errors and idling from incorrect synchronization. |
| D04 | P2 / validation | Give dynamic resolution real GPU time in Vulkan; today it gets `gpu_ms=-1` and reacts to the interval between presents, which also includes CPU/loading. Test 30↔60 transitions. | A stable scale at 30/60 when the GPU has headroom; it drops only under sustained pressure; no noticeable oscillation in menus/battles. |
| D05 | P2 / validation | Compare SMAA on/off, anisotropy, post-processing, fine textures and true internal resolution at 1080p/1440p/4K. Do not add TAA without motion vectors, history and a ghosting test. | Capture pairs and GPU cost, with no blurred UI, new shimmering, misaligned shadows or a relevant latency increase. |
| F01 | P1 to promote 60 / validation | Measure position, movement, animation, camera, scripts, battle, capture, audio and clocks at the **same seconds of gameplay** at 30 and 60. A present counter alone is not enough. | A comparative suite per scene in both games; deviation quantified and explained. |
| F02 | P1 to promote 60 / validation | Complete the map of frame counters and readers of the `G` table / steps 0 and 1; test menus, Pokédex, cutscenes, transitions and interactions between modes. | A list of the functions and subsystems covered, with no speed-up or freeze when changing scenes. |
| F03 | P2 / research | Improve in-between frames only with a stable object identity and handling of cuts, bones, shadows, UI and effects. The generic prototype was removed because of ghosts and deformations. | A frame-by-frame and in-motion visual comparison; turned off per scene when there is no reliable identity. |
| F04 | P2 / research | Evaluate battle/capture at native 60 Hz after fixing counters and physics/timers, or keep 30 explicitly. | Mechanics, duration, audio and animation equal to 30 fps within the tolerance the test defines; no regression in either game. |

## Phase 4 — Product, quality and maintenance

| ID | Pri. / type | Work | Done when |
|---|---|---|---|
| M01 | P1 / validation | Create CI to build the **runtime without game files**, unit and static tests, analysis of scripts/formats and packaging of a test artifact. Keep the tests that need one's own game files on a local runner, outside the public CI. | A pull request fails on a build/test error; no game content, key, generated code or log goes into Git. |
| M02 | P1 / validation | Define a release checklist and a per-version report: clean binary, both games, required scenarios, save, audio, GPUs, Vulkan validation, performance, documentation and rollback. | A release only ships with attached evidence and published limitations; experimental tests have their own section. |
| M03 | P1 / observed | Fix divergences between `PROGRESS.md`, `BATTLE-MODE.md`, README and the code: there are old passages saying the game went back to 30 fps or listing the already implemented battle prototype as the next step. | Each document describes the current build and points to the history for earlier versions; a single support matrix. |
| M04 | P2 / validation | Improve diagnostics for the user: setup/version/driver errors, the cause of a crash, a copyable log and recovery instructions without needing the development environment. | Problem reports contain build, GPU/driver, title/version, configuration and the last error, without including saves/keys. |
| M05 | P2 / validation | Review pinned dependencies, hashes and licenses of the package (`make dist`), and reproducing the zip on a clean machine. | An inventory of components and licenses; a reproducible package with no unexpected dependency on local tools. |
| M06 | P2 / decision | Set a compatibility policy: Windows as the supported platform; Linux/Steam Deck only after a build **and** a real test. Distinguish a missing feature, a known defect and experimental in the launcher/README. | The public expectation matches the J05/J07 matrix, with no promise based only on compiling. |

## Optional track — new features

These items should not delay stabilizing the original experience at 30 fps. If offered as official options, they go through the same regression and parity gates.

| ID | Pri. / type | Work | Done when |
|---|---|---|---|
| O01 | P2 / observed | Complete the experimental wild battles: split XP, nature/shiny/form, fleeing, the Pokémon disappearing from the map, encounter types and more areas (`docs/BATTLE-MODE.md`). | Cases per species/form/result, no corrupted save, and Eevee/Pikachu equivalent. |
| O02 | P2 / validation | Integrate and test the real gyro of compatible controllers, axis directions, calibration and drift; keep stick/mouse as the fallback. | A physical controller tested in capture and in long sessions; no relevant drift. |
| O03 | P3 / decision | Evaluate local co-op, the Poké Ball Plus and online integration only if there is scope, hardware and a test protocol. | The project decides to implement with full tests or to declare it unsupported with a safe way out. |
| O04 | P3 / decision | Evaluate Linux/Steam Deck as an additional port, considering Vulkan, audio, input, paths and distribution. | Real game, performance and install tests on the platform; compiling the inherited path is not enough. |

## Suggested order

1. **J01–J04, J06 and M03:** build gameplay, save and release coverage; fix any P0/P1 found. Run R01 alongside the script, since a visual reproduction already exists.
2. **J05, J07–J08, R02–R05 and M01–M02:** widen compatibility and remove presentation/first-use defects, with automatic and manual gates.
3. **D01 before D02–D05:** get baselines per hardware/scene. Optimization without a profile and a comparison does not count as a finished improvement.
4. **F01–F04:** promote 60 fps subsystem by subsystem, without changing the 30 default until speed and fidelity are validated.
5. **O01–O04:** new features according to product decisions and test capacity.

## Definition of a "mature stable version"

- The main campaign finished on Eevee and Pikachu in the announced builds, with intact saves and no reproducible blocker.
- The J04 critical scenarios pass on a clean release; no known P0/P1 without a fix or a specific public limitation.
- Vulkan rendering and synchronization verified on the announced GPUs; the aura and first-visit pop-in solved or classified with explicit impact and plan.
- Frame time, audio and memory baselines published for reference hardware; performance measured in gameplay, not inferred from an fps counter.
- A reproducible release without game content or keys, with install and diagnostics that work outside the development machine.
- 60 fps and wild battles only lose the "experimental" label when their own gameplay, timing and parity matrix is complete.
