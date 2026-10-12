# Windows native Tahoe implementation

The setup is ready for the Windows Hypervisor Platform prerequisite. This is
not a completed Tahoe installation or a Liquid Glass correctness claim.

## Sources and toolchain

- Reims base: steelbrain/reims-vgpu `9b2c5452de94a474cba28d80d7f99d9d7b19ffe3`.
- QEMU Windows branch: tqmane/qemu-reims-vgpu `22229b3d96b61578ee252abaf71c1912672fce5e`,
  based on `1a72df984914fb9929d35b1217619178133d65a4`.
- metal2vulkan Windows branch: tqmane/metal2vulkan `8556e6e4fe54fd8edcf45d48415242a2ac875421`,
  based on `13b279df1bf87893d389f955a90c55b6ff3d0f9b`.
- Native GNU Rust 1.98.1, MSYS2 UCRT64 Clang/LLVM/LLD 22.1.8,
  CMake 4.4.0, Meson 1.11.2, Ninja 1.13.2, Python 3.14.6 and cbindgen 0.29.4.
  All project caches and artifacts stay under the project. Existing MSYS2
  packages were updated; the before/after inventory is in private diagnostics.

## Implemented and verified

Windows guest RAM uses real retained section handles and page-aligned
MapViewOfFile3 aliases. The additive C config accepts old 48/56-byte callers;
its new sections field is at offset 56. Core clocks, threads, death tests,
IOSurface stand-ins, SDL3 Win32 windows and native Vulkan swapchains compile.
Read-only CPU views use writable import twins, with private zeros and import
lifetime retention. The runtime validates Windows pages before driver import.
The native QEMU has WHPX, the current apple-gfx-pci ABI, selective WHPX fixes,
correct q35 dirty-sync offsets and the current lockless BAR path.

The optimized Reims DLL and QEMU 11.1.50 build and execute on Windows.
UCRT64 must precede Rust's bundled DLLs on PATH; the environment helper does
this. Unused Curses, GnuTLS and Nettle backends are disabled: the existing
host libraries could not load, and Nettle 4 has an incompatible API. SDL,
localhost QMP and user networking remain enabled.

The supplied media was identified as APM/HFS+, macOS 26.4 build 25E246, with
an x86_64 PE booter. Its original was not changed. Exact file details and
SHA-256 are private in vm/state/media.json.

OpenCore 1.0.8 is from its official release and passes ocvalidate. The FAT
EFI image, matched QEMU OVMF pair, native-built Reims option ROM and 128 GiB
sparse qcow2 overlay chain are prepared. iMac20,1/j185 is configured; CSR is
zero, signed DMG loading is required, and no AMFI disabling argument is set.
Sample identity values do not provision Apple online services.

A paused TCG diagnostic realized PCI 106b:eeee with 8 vCPUs and 8 GiB RAM.
PCI/memory QMP queries, device reset, normal QMP quit and a second start/stop
worked. A native window titled Reims vGPU opened at 1920x1080 and presented
through MAILBOX on the Vulkan swapchain. This diagnostic never ran a guest
CPU. Normal start refuses unavailable WHPX and does not fall back to TCG.
The prepared snapshot is an empty install baseline, not an installed macOS.

The selected RTX 4070 SUPER, Windows driver 616.56, passed native host-import,
CPU/GPU copy/fill and authored Metal AIR compute-pipeline tests. See
TEST_RESULTS.md for scope and KNOWN_ISSUES.md for remaining checks.

## Required user step and continuation

Run scripts/windows/enable-whpx.ps1 in an administrator PowerShell, save
other work and restart Windows. Then run doctor.ps1 -RequireWhpx and
start.ps1. Only the user may accept the installer agreement and enter account
credentials. The accompanying Apple license must be considered; see
windows-vm.md and windows-native-audit.md.

WHPX guest boot, installation, desktop/reboot, Liquid Glass and workload FPS
remain unverified. No 60/120 FPS result is claimed. Private evidence is in
.work/diagnostics/ and vm/logs/. Generated binaries, guests and logs are ignored.
