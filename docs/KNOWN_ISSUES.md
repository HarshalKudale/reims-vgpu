# Known issues

Updated 2026-10-14. See [TEST_RESULTS.md](TEST_RESULTS.md) for current checks;
installation-era limitations in older revisions are not the current status.

## WebGL initialization remains open

On the preserved Tahoe 26.4 baseline, Safari returns already-lost WebGL 1/2
contexts (`CONTEXT_LOST_WEBGL`); Chrome fails EGL/GPU initialization. The
native Metal source/compute/readback probe passes. The guest PCI Metal device
reports Mac1, no Mac2 and no Apple families. ANGLE's default Metal backend
requires Mac2 or Apple1. This is an identified compatibility blocker, not
proof that the runtime's texture-coherence update repairs WebGL.

Changing the family mask or ignoring the browser's requirement is not a
correctness fix. No such override, software fallback or visual-effect
reduction is used. Browser shader, readPixels and context-recovery acceptance
remain blocked until a valid context exists. Details and primary source are
in [WEBGL_DIAGNOSIS.md](WEBGL_DIAGNOSIS.md).

## Display width and stalls

Upstream documents an x86 Tahoe WindowServer/plugin tile-texture failure
above 2048 pixels wide. Initial validation uses 1920x1080. The manager warns
about this risk and retains higher resolutions. A 4K mode being available
is not proof of stable WindowServer operation; 1440p/4K qualification is open.

Restored Xcode/Simulator processes can perform substantial background work.
During baseline shutdown, Simulator services took time to exit; eventually
QMP reported `shutdown` and QEMU exited normally. The 50-second ACPI deadline
was exceeded on this run. This does not establish a GPU deadlock. Guest app
termination, host/window progress and QMP power state must be distinguished.

## Performance and remaining validation

- The reported stable 60 FPS is not yet reproduced as a qualified run. Safari
  TestUFO showed sync failure. A first 30-second baseline under restored guest
  load averaged 38.45 guest/window callbacks per second; this is not monitor
  scanout or a browser FPS assertion.
- Frame timestamps measure QEMU guest-frame callbacks. Window GPU statistics
  include host submission/completion latency, not hardware timestamp queries.
  NVIDIA samples cover the whole selected adapter, including other host apps.
- The initial full check had ten strict render failures on unmeasured private
  memory and one invalid Windows-only negative fixture. Calibration preserves
  strict policy; final gate results must be read separately.
- macOS behavior-lock tests require their macOS runner. No WSL, Linux VM,
  Docker or substitute renderer is used. The Windows C harness is not the
  full macOS suite.
- Full device-loss stress, sustained guest resource reuse and all-resolution
  visual qualification remain open. OS/driver-owned caches are not controlled
  by project cache paths.

The old RTCLOCK 6.4 GHz mismatch did not recur in the latest baseline boot:
XNU logged 3.190 GHz with a 3.187198 GHz calibration. This does not by itself
prove clock equivalence or exclude timeout problems under other conditions.
