# Known issues

- WHPX boots the Tahoe 26.4 recovery UI with eight CPUs after correcting
  Haswell stepping and the core/thread count MSR. GPT/APFS preparation is
  complete. The user accepted the agreement; installation stage 1 copied
  approximately 17.76 GiB and reached its automatic restart.
- That warm reset failed under WHPX: XSAVE reads returned HRESULT 80370301,
  then virtual processors exited with unrecoverable exception code 4 and
  QEMU paused. A full process restart preserved the disk and reached its
  new macOS Installer entry. Warm reset still needs a source fix and proof.
- XNU reported RTCLOCK 6.4 GHz, while the Windows hypervisor capability and
  native RDTSC/QPC measurement report about 3.187 GHz. Clock calibration is
  being investigated; installer remaining-time and performance claims need
  this discrepancy resolved.
- Recovery ignored QMP system_powerdown within 15 seconds. Its Terminal
  shutdown command exited cleanly; installed-system shutdown is unverified.
- Completed installation, account setup, desktop/reboot,
  Finder/Dock/Safari, Liquid Glass and sustained FPS have not been exercised.
- One legacy core test, tasks::shared::tests::data_from_virtual_offset::
  a_length_past_any_task_raises, requires a normal 32 GiB Vec allocation.
  It aborts on the current Windows memory/commit limit and remains unchanged.
  The other 2301 core tests passed serially. Large fake raw regions use
  sparse temporary files, preserving their zero-filled real address space.
- No macOS behavior-lock suite or Mac runtime check was run. Linux shared
  sources were type-checked on the Windows host; this is not a Linux execution
  claim or a substitute for Windows guest evidence.
- Window GPU statistics currently use the runtime's host-clock interval,
  which includes submission/completion latency. They are not pure hardware
  GPU start/end timestamps. Absolute Metal clock equivalence, calibration,
  shader/cache/lock profiling and 1% low workload measurement remain open.
- Native copy/fill/pipeline and QMP shutdown passed. Full GPU stress/device
  loss, DLL unload under loader lock, mixed-CRT shutdown under guest load,
  long-running resource reclamation and guest-page reuse still need checks.
- Runtime labels the Windows NVIDIA driver identity unmeasured and selects
  its exact paths. These paths are not proof of Tahoe UI rendering correctness.
- NVIDIA/Windows internal driver and OS caches are not controlled by the
  project environment. Explicit project data remains under the project.
