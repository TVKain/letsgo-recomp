# Analysis of LASRecomp → feasibility of a Pokémon Let's Go Eevee recomp

_Historical document: the feasibility analysis made before starting. The current state is in
[PROGRESS.md](PROGRESS.md)._

Date: 2026-10-14 · Reference: `reference/LASRecomp` (commit cloned with `--depth 1`, MIT license, © 2026 Peiikai)

## TL;DR

LASRecomp is **not a port "tied" to Link's Awakening**: its core is a generic static recompiler for the Switch (NSO
ARM64 → C) and a runtime that reimplements Horizon OS and the **NVN** graphics API by function name. What is specific
to Zelda sits in separable layers (patches by address, randomizer features, UI). For Let's Go, the strategy is to
**fork the core, remove the Zelda layer** and fill in what is missing (services, NVN functions, audio), guided by the
"UNIMPLEMENTED" logs.

Feasibility: **good on paper**. The real risk only shows when we run the generator over Let's Go's `main` (binary size,
extra modules, services and NVN functions Zelda never used).

## How LASRecomp works (pipeline)

```
extracted/exefs/main, sdk   (NSO, from the player's own game files)
        │
        ▼  tools/nso.py      decompresses LZ4, builds the image, reads MOD0 / symbols / relocations
        ▼  tools/analyze.py  finds functions (eh_frame + symbols + RELATIVE relocations)
        ▼  tools/lifter.py   translates each ARM64 instruction → C   (Capstone)
        ▼  tools/gen.py      generates C per module; resolves jump tables by emulating with Unicorn
        ▼  tools/passes.py, tools/patches.py   optimizations + patches by address (widescreen etc.)
        ▼  clang/zig cc      → lasgame.dll (the game's code, generated ON THE PLAYER'S MACHINE)
        │
lasrecomp.exe (runtime) ── loads lasgame.dll + reads the RomFS
```

- `make gen` runs `gen.py sdk … 0x7004000000 --hle hle_symbols.txt` and `gen.py main … 0x7000000000`.
- Guest addresses == host addresses (a window reserved at `0x70_0000_0000`, see `runtime/rt.h`).
- The launcher checks `main`'s **build id** (`runtime/ui/launcher.mm:85`) to make sure it is v1.0.0.

## What is generic (reusable) vs. specific to Zelda

| Part | Files | Generic? | Note for Let's Go |
|---|---|---|---|
| NSO loader / relocation | `tools/nso.py`, `runtime/loader.c` | ✅ | Loads only `main` + `sdk` (fixed in `loader.c:177`). If Let's Go has `subsdk*`, it must be extended. `SDK_BASE` = main + 64 MB: check that Let's Go's `main` fits. |
| ARM64 → C lifter | `tools/lifter.py`, `tools/gen.py`, `tools/analyze.py`, `tools/passes.py`, `tools/simd_c.py` | ✅ | Unsupported instructions become `rt_udf()` and show in the statistics: coverage can be measured right away. |
| CPU / SIMD in C | `runtime/cpu.h`, `simd.h`, `simd_fp.h` | ✅ | x86-64-v3 (AVX2, FMA) or, without AVX2, x86-64-v2 with the fused operations emulated (same result). |
| Kernel (SVCs) | `runtime/kernel.c` | ✅ | ~40 SVCs: threads, sync, memory, events. Covers the basics of any game. |
| IPC / services | `runtime/ipc.c`, `runtime/services/*` | 🟡 | Already has acc, aoc, apm, audout, audren, fs/save/sdcard, hid, lm, pctl, set, time. Let's Go probably asks for more (e.g. nifm, friends, ldn/local communication, bluetooth/Pokémon GO, pl/fonts). Most can be stubs ("no network"). |
| HLE by symbol | `runtime/dispatch.c`, `runtime/hle.h` | ✅ | A function called but not implemented → logs `[hle] UNIMPLEMENTED <name>` and returns 0. Great for finding what is missing. |
| HLE of SDK libraries | `hle/heaps.c`, `hle/input.c`, `hle/vi.c`, `hle/swkbd.c`, `hle/framepace.c` | 🟡 | nn::lmem, nn::mem, nn::hid, vi… generic, but covering only the variants Zelda uses. |
| **NVN (GPU) → Vulkan** | `runtime/nvn/*` (495 NVN functions implemented), `nvn/vulkan/*` | 🟡 | Implemented at the **NVN API**, by name (`hle/nvn_boot.c`), so it applies to any NVN game. Functions Zelda does not use are missing (e.g. `nvnTextureReadTexels` logs "not implemented"). |
| Maxwell shaders → SPIR-V | `runtime/nvn/maxwell/translate.c` (~2100 lines) | 🟡 | Generic in principle, but only tested with Zelda's shaders. The biggest risk for graphics bugs. |
| Audio | `runtime/services/audio.c` | 🟡 | audren mixer based on Ryujinx's. **Effects and splitters not implemented**: if Let's Go uses reverb etc., they must be added. |
| Video (cutscenes) | `hle/movie.c` (FFmpeg) | 🟡 | Implements the `nn::movie` library Zelda uses. Let's Go may use another video library. |
| Patches by address | `tools/patches.py` (48 addresses), `nvn/metal.m:589` | ❌ | Zelda's widescreen and culling. Drop them and redo for Let's Go later. |
| Game features | `hle/{chamber,digs,doorjump,escape,hookshot,keysanity,miniboss,pets,pot_glow,rescue,shopsanity,souls,warp,qol,flags_ext,pl}.c`, `rando.c`, `tools/rando/*`, `third_party/LAS-Randomizer` | ❌ | Zelda's randomizer and QoL. Remove. |
| UI | `runtime/ui/*` (ImGui) | 🟡 | The launcher and menu are reusable as a skeleton. The rando/warp/tracker/save editor tabs go. |
| Platform | `runtime/platform/*`, Windows build via MSYS2 UCRT64 | ✅ | `docs/BUILD-windows.md`. |

## What we will only know from the game's own files

1. **ExeFS modules**: only `main` + `sdk`, or are there `subsdk0..N`?
2. **Size of `main`**: does it fit in 64 MB below `SDK_BASE`?
3. **Lifter coverage**: how many instructions become `rt_udf` (unsupported).
4. **Imported functions**: which `nn::*` and `nvn*` the game calls that the runtime does not have yet.
5. **IPC services** asked for at boot.

All of this comes from running `tools/nso.py` and `tools/gen.py` over the extracted `main`/`sdk`, before building
anything.

## Proposed plan

**Phase 0: prepare (now)**
- [x] Clone LASRecomp as a reference.
- [ ] Put the player's own extracted game files in `extracted/exefs` and `extracted/romfs` (folders already in
      `.gitignore`).
- [ ] Set up the Windows environment (MSYS2 UCRT64, clang, SDL3, FFmpeg, shaderc, Python + capstone/unicorn/lz4).

**Phase 1: diagnostics (without building the game)**
- Run `nso.py` on `main`/`sdk`: modules, sizes, imports.
- Run `gen.py` and measure unsupported instructions.
- Cross the imports with what the runtime already implements → list of what is missing.

**Phase 2: lean fork**
- Copy the core (lifter, loader, kernel, ipc, services, nvn, platform, base UI) to `src/`.
- Remove the Zelda layer (patches, rando, gameplay HLE, BUILD_ID).
- Parameterize modules/bases in the loader.

**Phase 3: boot**
- Goal: the Game Freak logo / title screen, even with broken graphics.
- Loop: run → read `UNIMPLEMENTED` / crash → implement → repeat.

**Phase 4: playable**
- Pallet Town, battles, menus, saves, audio. Then widescreen and improvements.

## Project rules

- **Nothing from the game goes into git**: `extracted/`, `generated/`, game images and packages, keys.
- The game's code is generated on the machine of whoever owns the game, as with LASRecomp. Releases never include
  Nintendo/Game Freak code or assets.
- A personal / study project. Publishing carries legal risk (Nintendo/The Pokémon Company).
- License of the reference code: MIT. Keep LASRecomp's copyright notice in any derived file.
