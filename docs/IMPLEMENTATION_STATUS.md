# Windows native Tahoe: current implementation

Updated 2026-10-14. The installed Tahoe 26.4 desktop, Finder, Dock, Safari,
Apple Account sign-in and JIS input worked before this synchronization.
The initial installation notes in older revisions are historical.

## Preserved working environment

The owner checkout remains on `windows-native-tahoe` at `68d0a4d7`; its QEMU
is `c1dbb187`, runtime `8556e6e4`. The production disk, OpenCore, NVRAM and
engine have not been replaced by a candidate. Private backup hashes and the
original engine are under `.work/diagnostics/upstream-sync-20261014/baseline`.
Git baseline refs are `steelbrain/baseline-windows-20261014` in all three repos.

Development uses `windows-native-tahoe-upstream-sync-20261014`, based on the
working Windows branches. See [UPSTREAM_SYNC.md](UPSTREAM_SYNC.md) for the
upstream classification, exact commits and integration decisions.

## Implemented in the development branch

- Merge upstream Reims, its dedicated QEMU branch and metal2vulkan while
  retaining WHPX topology/reset, Win32 section aliases and lifetime handling,
  native SDL3/Vulkan, JIS input, USB selection, management and OpenCore scripts.
- Adapt upstream HostMemory to the retained Windows import validation and
  Linux dma-buf support; keep the additive C interface and correct QEMU pin.
- Run the C host harness natively on Windows with real retained sections.
- Preserve the unfiltered 32 GiB core boundary test with a test-only sparse
  file allocator; no production allocator or boundary comparison changes.
- Add authored WebGL 1/2 pixel/context regression inputs and a dynamic Metal
  source-compilation/readback probe. The collector is loopback-only.
- Add optional timestamped frame-callback and NVIDIA adapter sampling to
  `scripts/windows/benchmark.ps1`, with parser self-checks.
- Show the known width-over-2048 Tahoe risk in the manager without removing
  the 1440p or 4K choices.

The runtime also has a measured, conservative 16 KiB Function-storage bound
for RTX 4070 SUPER on Windows NVIDIA 616.56, guarded by the exact driver
version. No larger private-memory budget is enabled. Authored native texture,
BC3 edge-copy and private-memory checks use Vulkan validation.

## Verification state

The synchronized release and QEMU built; native ABI and memory checks passed.
Final dependency rebuild and guest comparison are in progress. The initial
full library check was not green: 11 failures were investigated rather than
filtered. See [TEST_RESULTS.md](TEST_RESULTS.md) for the completed evidence.

**WebGL is not fixed or qualified.** The baseline browser fails during
context initialization even though an authored native Metal kernel compiles
and returns correct bytes. See [WEBGL_DIAGNOSIS.md](WEBGL_DIAGNOSIS.md).
Neither the upstream merge nor native GPU tests are a WebGL pass.
