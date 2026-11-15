# Research: where the GPU spends the world's frame

_2026-10-17/18. Eevee 1.0.0, RTX 3080, a Route 1 route (`build/audit-save-20261017`, world standing still, ~600 draws
per frame), internal resolution 1920x1080. **Solved**: the GPU read the vertices over PCIe. The fix and numbers are
below; what is still open is at the end._

## Summary

- The game drew the world with ~9-10 ms of GPU per frame, most of it in **4 draws** (instanced, vegetation) that
  produce almost no image.
- The cause was neither the shader nor the pixels: vertices and indices were read **straight from the game's memory
  imported into the GPU** (system memory), over PCIe, on every vertex shader invocation. Each instance has 8 streams of
  16 bytes, reread for each of the draw's ~71 thousand vertices: ~9 MB per draw, ~0.8 ms at ~11 GB/s.
- On discrete cards the vertices and indices now go to VRAM (staging in system memory + a copy at the start of each
  submission). Ranges the game itself writes by compute are still read in place. GPU: **10.2 -> 1.2 ms per frame
  (-88%)**; uncapped fps in the world **~75 -> ~90 (+19% at the median)**, because the CPU pays ~1.8 ms for the copies.
- On integrated GPUs (system memory is the GPU's memory) the old behaviour was kept.

## A warning about the method

**The GPU time of the same frame varies from ~10 to ~18 ms from one run to another with the same code.** Comparing two
separate runs only works for large effects (2x or more). Several early conclusions of this research ("stacks as
vectors: -11%", "flattening the state machine: -12%") were noise and were disproved by interleaved tests. For smaller
effects, alternate the versions **within the same run** (`LARECOMP_EXP_ALT=1`: the changed version only on odd frames,
a profile of 70 frames in a row, compare the medians of even and odd) or interleave several A/B runs and use only
world frames (the `[gpuprof]` header at 6 ms or more). The image is not identical between two runs of the same mode
either (~34 dB PSNR: the Pokémon walk around), so "equal" can only be measured against that noise. Tools:
[DEBUGGING.md](DEBUGGING.md).

## How the cause was found

1. **The GPU frame is a single pass.** `LARECOMP_GPUPROF_AT`: the main HDR 1920x1080 pass with 316 draws = 84% of the
   time; the 2048x2048 shadow map = 1.6 ms; all the post-processing together, under 1 ms.
2. **A group of 4 draws costs ~4.9 ms** (a third of the GPU): the same pair of shaders, 1,404 indices x 180 instances
   each. In the same run, even frames with them and odd frames without: median 14.58 against 9.70 ms.
3. **The cost is vertex, not pixel.** A 1x1 scissor: -0.27 ms (nothing). `LARECOMP_GPUPROF_STATS`: 252,720 input
   vertices, ~71,176 vertex shader invocations, 0 fragments and 0 primitives after clipping in 5 of 6 samples.
4. **It is not the shader's math.** A vertex shader that only reads the 11 attributes and adds them costs the same as
   the full one (0.80 against 0.81 ms per draw); without reading the attributes (return at the start of `main`) it
   drops to 0.09 ms. The driver (`LARECOMP_PIPE_STATS`, `VK_KHR_pipeline_executable_properties`) reports 48 registers,
   10 KB of code and no spills: the compiled shader is small and efficient.
5. **The code had the reason**: `guest_direct` binds the game's imported heap as the vertex and index buffer, with no
   copy ("read in place", as on the Switch). The imported heap is system memory. This program's attribute layout: 1
   stream per vertex (24 bytes) and 8 streams per instance (`stride 16`, one `vec4` each).
6. **Decisive test**: `LARECOMP_VK_COPY_VERTICES=1` (copies into the ring): the same draw drops from 0.8 to 0.01 ms and
   the GPU frame from 9.2 to ~1 ms, with the same image.

## What was ruled out

| Hypothesis | Test | Result |
|---|---|---|
| 16x anisotropic filtering | `LARECOMP_ANISO=1` | same cost per index (4.8 against 4.5 ns), across runs |
| Pixel fill | 1x1 scissor, same run | no effect |
| Reading the memory ring over PCIe | the ring's log | the constants ring is in GPU-local memory; **it was the vertices that did not go through it** |
| `ssy/pbk/pcnt` stacks in local memory | `uvec4` instead of `uint[16]`, interleaved A/B | median 12.39 against 12.88 ms; change reverted |
| The `for + switch (pc)` state machine | shader converted by hand into blocks without the loop | 0.73 against 0.83 ms per draw, within noise |
| `robustBufferAccess` | `LARECOMP_NO_ROBUST=1` | inconclusive (drift between runs) |
| Shader ALU | GLSL and driver stats | 427 instructions, no loop, no spill |

## The fix

`runtime/nvn/vulkan/exec.c`:

- **Two rings.** Ring 0 (as before) holds the constants and the texture upload sources. Ring 1 holds the draws'
  vertices and indices: a staging chunk in system memory the CPU writes to, and a chunk in VRAM the GPU reads from; at
  the start of each submission (`ring_flush_gpu`) what was written since the previous one is copied through the upload
  buffer, which already runs before the main one with a barrier.
- **Ranges the GPU writes** (`gpuw`): this game uses compute to generate vertex data (a compute writes 16-byte buffers
  that two vertex programs read as streams). The storage buffers bound to a compute (or to a vertex or fragment shader
  with `STG`) go into a set of sorted ranges; vertices and indices inside them are still read in place, when the GPU
  runs, and never copied at draw time. If a shader writes global memory **without** any storage buffer bound, the
  runtime reads everything in place from then on (a warning in the log).
- **Policy**: `LARECOMP_VERTEX_READ=direct|copy|auto` (default `auto`: copy on a discrete card, in place on an
  integrated one).
- **Fewer bytes**: copies keyed by start address (a draw wanting a shorter prefix reuses another's copy) and, for
  per-vertex streams, the whole bound buffer (up to 8 MB) the first time: 37.3 MB per frame became 16.2 MB. The
  max-index scan uses AVX2.

## Result (Eevee, RTX 3080, Route 1 world, interleaved runs)

| | direct | hybrid (default) |
|---|---:|---:|
| GPU per frame | 10.2 ms | 1.2 ms |
| uncapped fps (median of 11-13 windows) | 75.1 | 89.6 |
| extra CPU per frame (copies) | 0.04 ms | 1.8 ms |
| paced 60 fps: mean / P99 | 60.0 fps / 17.4 ms | 60.0 fps / 17.3-18.6 ms |

With 2x internal resolution (the GPU starts to weigh) the hybrid held ~79.7 fps against 70.6-76.0 for direct. Uncapped
fps rises little on a 3080 because the CPU is the limit; the big gain is for weaker GPUs or slower PCIe, where those
~9 ms of reading over the bus become the bottleneck (the 9 ms figure holds for this machine; no other was measured).

## What was tried to lower the CPU cost and was not kept

- Staging in cached memory and a vectorized index scan: no measurable effect (the cost is the volume copied).
- Windows' **write watch** (`MEM_WRITE_WATCH`) to keep the meshes in VRAM between frames and copy only what the game
  wrote: the game writes only ~500-1,900 pages per frame (2-7 MB), but `GetWriteWatch` over the whole heap costs
  ~2.3 ms per call, and per range ~2.3 us (~300 ranges per frame: ~0.7 ms per submission). A small gain for the
  complexity and risk; reverted.

## The chain between the game's threads

- Only **3 threads work** (ids 80, 81, 82, priority 44), each at ~40% CPU (~1.15 cores in total); the other 7 sit 100%
  idle on a condvar. Measured with `LARECOMP_THREAD_DUMP=16,0.25` and CPU per thread.
- When they "run", they are in `nvnQueueSubmitCommands` or `nvnQueuePresentTexture` (`LARECOMP_HLE_WHO` gives the
  names): the Vulkan backend executes the command list **inside the call, on the game's thread**.
- With the GPU at ~1 ms, uncapped fps stays at ~90 (an ~11 ms cycle): **the limit is now the CPU chain between the
  three threads**, which take turns instead of overlapping. That is the next target.

## Next steps

1. **The CPU chain between the threads**: move `backend_execute` off the game's thread (a render thread with a queue)
   and find out why the three take turns. Estimated ceiling: the cycle drops to the longest thread's.
2. **Copies in parallel** (workers) or a cache between frames with another way of detecting writes: lower the ~1.8 ms.
3. Measure on a weaker GPU and an integrated one (the `auto` policy assumes an integrated GPU gains nothing from
   copies).
