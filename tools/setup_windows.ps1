# One-time preparation of a Windows machine to build Let's Go Recomp (docs/BUILDING-WINDOWS.md).
# Installs MSYS2 (clang, lld, make, SDL3, FFmpeg, Vulkan, shaderc) and Python 3.12, creates the generator's .venv
# (capstone, unicorn, lz4) and sets the clone to LF line endings. Safe to run again.
# Adapted from LAS Recomp's tools/setup_windows.ps1 (without the randomizer).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path C:\msys64\usr\bin\pacman.exe)) {
    winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements --silent
}
$env:MSYSTEM = 'UCRT64'
$env:CHERE_INVOKING = '1'
$bash = 'C:\msys64\usr\bin\bash.exe'
& $bash -lc 'pacman -Syuu --noconfirm' | Out-Null
& $bash -lc 'pacman -Syuu --noconfirm' | Out-Null  # second pass after a core update
$pkgs = 'make', 'mingw-w64-ucrt-x86_64-clang', 'mingw-w64-ucrt-x86_64-lld', 'mingw-w64-ucrt-x86_64-sdl3',
        'mingw-w64-ucrt-x86_64-ffmpeg', 'mingw-w64-ucrt-x86_64-vulkan-devel', 'mingw-w64-ucrt-x86_64-shaderc',
        'mingw-w64-ucrt-x86_64-spirv-tools', 'mingw-w64-ucrt-x86_64-pkgconf', 'mingw-w64-ucrt-x86_64-gdb',
        'mingw-w64-ucrt-x86_64-vulkan-memory-allocator', 'mingw-w64-ucrt-x86_64-vulkan-validation-layers'
& $bash -lc "pacman -S --needed --noconfirm $($pkgs -join ' ')"

# Python from python.org (it has prebuilt unicorn / capstone wheels; MSYS2's Python cannot build them)
$py = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
if (-not (Test-Path $py)) {
    winget install --id Python.Python.3.12 -e --scope user --accept-source-agreements --accept-package-agreements --silent
}
if (-not (Test-Path "$root\.venv\Scripts\python.exe")) { & $py -m venv "$root\.venv" }
& "$root\.venv\Scripts\python.exe" -m pip install -q lz4 capstone unicorn

# LF line endings in this clone (the bash scripts break with CRLF; Git for Windows uses autocrlf=true by default)
git -C $root config core.autocrlf false
git -C $root config core.eol lf
Write-Host 'Done. Build in an MSYS2 UCRT64 shell (or in Git Bash with C:\msys64\ucrt64\bin;C:\msys64\usr\bin on the PATH): make -j20'
