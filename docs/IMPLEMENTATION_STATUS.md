# Windows native Tahoe implementation

The development branch starts from Reims `9b2c5452de94a474cba28d80d7f99d9d7b19ffe3`,
QEMU `1a72df984914fb9929d35b1217619178133d65a4` and metal2vulkan
`13b279df1bf87893d389f955a90c55b6ff3d0f9b`.

Windows-native Rust 1.98.1 GNU and MSYS2 UCRT64 LLVM 22.1.8 are installed.
An LLVM-produced Windows executable compiled and ran. The option ROM's EFI
driver linked on Windows; its relocation-free ROM object can be extracted
with `llvm-objcopy`. The Windows make recipe uses that path because MSYS2's
`ld.lld` is a COFF linker. The source checkout uses LF to preserve the committed
metallibs' source fingerprints.

Windows shared-section memory views, clock/thread services, SDL3/Vulkan window
wiring and DLL distribution are being implemented. Builds and native checks
are still in progress. This file will be updated with their final results.

WHPX is currently blocked: Windows Hypervisor Platform is disabled, BIOS
virtualization is enabled, and `WHvGetCapability` reports no hypervisor.
Enabling the feature needs an administrator PowerShell and a Windows restart.
`scripts/windows/enable-whpx.ps1` performs the feature change without restarting.

No macOS installation, desktop, Liquid Glass correctness or FPS claim has been
verified. The installer agreement must be accepted by its user.

Private machine details and intermediate logs are in `.work/diagnostics/`.
VM media and state are under `vm/`; both directories are ignored by Git.
