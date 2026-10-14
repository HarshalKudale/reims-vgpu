# WebGL diagnosis on the Windows native Tahoe guest

Updated 2026-10-14. **WebGL acceptance is not complete.** Native Metal working,
upstream synchronization and a non-null JavaScript object do not establish a
working WebGL context.

## Reproduction and observations

Use the authored page in `tests/webgl` in the real guest, without GPU force
flags, family overrides or a software renderer. It records WebGL 1 and 2
separately and posts stage-by-stage JSON to a loopback-only host collector.

| Layer | Preserved baseline observation |
|---|---|
| Safari 27 on Tahoe 26.4 | WebGL 1/2 objects exist but are already lost; version/renderer null, error 37442 (`CONTEXT_LOST_WEBGL`) |
| Chrome 155 | WebGL 1/2 getContext null; EGL initialization and GPU-process initialization fail |
| Native Metal device | Apple Paravirtual device, non-headless, Mac1 yes, Mac2 no, Apple1 through Apple10 no |
| Native Metal source / pipeline | Authored source compiles and creates a compute pipeline |
| Native GPU completion/readback | 64 uint outputs match the authored kernel |
| Host protocol | x86 guest requests binary version 6; argument buffers off |

The Safari failure occurs before shader compilation or texture readback.
Chrome independently confirms an initialization failure; its disabled GL
implementation report does not identify a successful alternate renderer.
The WebKit GPU process remained alive in the baseline capture; no new WebKit
GPU crash report was found. This does not prove long-run process stability.

## Compatibility blocker

ANGLE's current Metal initialization defaults `requireGpuFamily2` on and
rejects a device unless it supports Apple1 or Mac2. Its helper checks those
two families, not Mac1. See the primary
[ANGLE Metal implementation](https://raw.githubusercontent.com/google/angle/main/src/libANGLE/renderer/metal/DisplayMtl.mm)
(`initializeImpl`, `initializeFeatures`, `supportsEitherGPUFamily`).

The measured guest capability answers fail that gate. This explains an
initialization blocker and is consistent with the browser results. Matching
source from the exact shipped Safari/Chrome build has not been established,
so it is not claimed to be the only failure in either browser.

The PCI guest device inherits its family query from Metal's base class; the
host's newer Apple-family device-info fields do not establish that this
legacy guest exposes them. A valid fix needs a supported guest/browser path
with the required capabilities implemented and exercised. Setting Mac2 yes
without that proof, ignoring the gate or force-enabling the browser would
hide the blocker rather than repair it. None was applied.

## Regression inputs and acceptance

`tests/webgl/suite.js` includes context creation, authored shader compile/link,
triangle/VBO pixels, texture upload, FBO/readPixels, blend/depth, repeated
frames, resource lifetimes, context loss/recovery and unexpected-loss checks.
It rejects known software fallback renderer strings. `metal-probe.m` checks
dynamic Metal source compilation, completion and CPU-visible GPU results.

A context lost during initialization is reported as that failure rather than
as a later shader error. Missing or failed earlier stages cannot yield a
successful overall result. Browser JSON, QMP screens, serial and host logs
must be matched by run and timestamp. The same page's success on a different
host is useful fixture validation, not proof of guest correctness.

To accept a fix: both real guest APIs must compile/link and render expected
pixels, recover a deliberate context loss, remain stable under repetition,
and show correct browser output with no new host fatal or Vulkan validation
errors. These stages remain blocked on the current baseline.

## Related issues kept separate

`METAL_ERROR_MODE=5` was confirmed in the guest; it addresses binary-archive
assertions, not this context failure. SIP/AMFI remain enabled. The 1080p
reproduction avoids the separate wide-display WindowServer issue. Native
copy/fill/texture tests establish their own semantics only. No Apple shader
binary, cache, serialized guest descriptor or extracted Apple code is
committed with this report.
