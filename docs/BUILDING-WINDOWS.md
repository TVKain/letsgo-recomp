# Building and playing on Windows

Step by step from nothing to the game running, from the source code. **To just play, use the release** (the zip in
Releases, see the [README](../README.md#how-to-play)): it needs none of this.

It takes about half an hour, almost all of it waiting for downloads and the build.

## What you need
- Windows 10 or 11, 64-bit
- A CPU with SSE4.2 (Intel from 2008 / Nehalem, AMD from 2011 / Bulldozer); with AVX2 (Intel from 2013 / Haswell, AMD
  from 2015 / Excavator) the game's code runs faster. `make` builds the game's code for `GENARCH` (default
  `-march=x86-64-v3`; `GENARCH=-march=x86-64-v2` for a CPU without AVX2, deleting `build/obj/` first: the objects do
  not depend on the flags); the start screen picks by itself from the CPU
- A GPU with Vulkan 1.3 and an up-to-date driver (recent NVIDIA, AMD or Intel)
- About 10 GB free (game files, generated code and build)
- [Git for Windows](https://git-scm.com/download/win) (it brings Git Bash)
- **Your own game files**: *Pokémon: Let's Go, Eevee!* or *Pikachu!*, extracted from your own copy (Eevee **v1.0.0**
  is the most tested; the experimental options need 1.0.0 of either game or Eevee 1.0.2). This project neither
  provides these files or the keys nor explains how to get them.

## 1. Get the project
In Git Bash, in a folder with free space (preferably outside `Program Files`):

```bash
git clone https://github.com/raulzrrs/letsgo-recomp.git
```

## 2. Install the tools (once)
In PowerShell, inside the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1
```

The script installs:
- **MSYS2** in `C:\msys64`, with clang, make, SDL3, FFmpeg, Vulkan and shaderc;
- **Python 3.12**, with the code generator's environment in `.venv`.

It also sets the clone to LF line endings. You can run it again if something fails partway.

## 3. Build the runtime
Open **Git Bash** in the project folder and put MSYS2 on the PATH (for that window):

```bash
export PATH="/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH"
make -j20 build/lasrecomp.exe
```

This produces `build/lasrecomp.exe`, the runtime (the launcher and everything that stands in for the Switch). Runtime
changes rebuild in seconds.

## 4. Set up the game from the launcher (the simplest way)

```bash
./build/lasrecomp.exe
```

In the launcher, click **Select game folder...** and choose the folder with the extracted game (the one with `exefs`
and `romfs`, or a `romfs.bin`). It checks whether it is Eevee or Pikachu (program id), copies the files to
`extracted/`, generates the game's code with the `.venv` and builds it with MSYS2's clang (`extracted/lasgame.dll`).
It is the same flow as the release, with the development tools in place of the frozen generator and Zig. Then click
**Play**.

## 4b. Or by hand
Create the `extracted/` folder at the project root with:

```
extracted/
  exefs/      main, main.npdm, rtld, sdk, subsdk0, subsdk1   (the game's ExeFS)
  romfs.bin   the game's RomFS image (about 4.4 GB)
  romfs/      optional: the RomFS extracted into folders (useful for mods; the game reads romfs.bin)
```

The generated code depends on the exact executable: the generator's patches (`tools/patches.py`) and the runtime's
hooks are addresses in `main` (a table per build: Eevee 1.0.0 and 1.0.2, Pikachu 1.0.0, `tools/addrmap.py`) and stay
off for any other. `extracted/` is in `.gitignore` and must never go into git.

Translate the game's code to C (the result goes to `generated/`, outside git) and build. **Always with `-j`**: without
it the game's ~920 files build one at a time and take over an hour.

```bash
make gen
make -j20
```

This also produces `build/lasgame.dll` (the game's code), in 5 to 20 minutes depending on the CPU.

## 5. Play

```bash
./build/lasrecomp.exe
```

- Saves go in `save/`, settings in `larecomp.ini` and the shader caches in `cache/`, all in the project folder.
- `--play` skips the launcher: `./build/lasrecomp.exe extracted --play`.
- `make jogo` builds in `build/jogo/` a copy that opens with a double click (it brings the MSYS2 DLLs) and lets you
  rebuild `build/` while playing.
- The first time in each area compiles the shaders. Objects may appear late for a moment; from the second time on it
  is smooth.

## 6. The release (the zip for those who just want to play)

```bash
make deps-windows          # LGPL-only FFmpeg, with the decoders the game uses (needs MSYS2's nasm)
make gen-helper            # the generator frozen with PyInstaller (no Python on the player's PC)
tools/fetch_zig.sh         # the Zig compiler, a fixed version checked by sha256
make dist                  # build/dist/LetsGoRecomp-<version>-windows.zip
```

The zip contains `LetsGoRecomp.exe`, the DLLs, the generator, a slimmed Zig (`tools/zig_slim.sh`) and the headers for
the game's code. Nothing from the game goes with it: the code is generated on the player's PC, from their own copy. The
version comes from `RT_APP_VERSION` in `runtime/paths.h`.

## Optional
- **Translations / mods:** in the launcher, **Mods** page, **Install mod...** and choose the downloaded file (.zip,
  .rar, .7z); it comes ticked in the list (several can be used together; if two replace the same file, the one higher
  up wins). You can also copy the mod's `romfs` to `mods/<name>/romfs` by hand (**Open the mods folder**).
- **The Switch's system font:** see [fonts/README.md](../fonts/README.md).
- **Better image:** with a GPU to spare, choose a resolution above your screen's (for example 4K on a 1080p screen):
  the game is rendered larger and scaled down, which removes almost all aliasing.

## Common problems
| Symptom | What to do |
|---|---|
| "avutil-…dll / SDL3.dll not found" when opening the exe | run it from Git Bash with MSYS2 on the PATH, or use the `make jogo` copy (it brings the DLLs) |
| the launcher asks to set up the game again | the generator or the headers changed: choose the folder again (or, by hand, `make gen` and `make -j20`) |
| `make gen` fails | check the `.venv` (run `setup_windows.ps1` again) and that `extracted/exefs/main` exists |
| black screen or a Vulkan error | update the GPU driver; Vulkan 1.3 is needed |
| the game closes by itself | send the terminal output (or the release's `lasrecomp.log`) in an issue (see [CONTRIBUTING.md](../CONTRIBUTING.md)) |

## For those working on the code
- [DEBUGGING.md](DEBUGGING.md): diagnostic variables and `tools/repro.sh`, which runs the game with scripted input and
  takes screenshots at chosen frames.
- [HISTORY.md](HISTORY.md): how each problem was solved. The best way to understand the runtime.
- Changed `runtime/cpu.h` or `runtime/gamelib.h`? The game DLL must be rebuilt (`make -j20`).
