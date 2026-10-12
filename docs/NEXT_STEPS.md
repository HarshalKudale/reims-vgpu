# Continue after the host prerequisite

1. Save other work. In an administrator PowerShell run
   scripts/windows/enable-whpx.ps1. It enables HypervisorPlatform without
   restarting. Restart Windows yourself when ready.
2. In the project, run scripts/windows/doctor.ps1 -RequireWhpx, then
   scripts/windows/start.ps1. The default path uses WHPX, 8 vCPUs, 8 GiB,
   the validated OpenCore/OVMF/ROM, native Vulkan and the retained installer.
3. Follow installer boot logs and diagnose actual WHPX CPU/device behavior.
   The user must handle the installer agreement and account credentials.
   Preserve SIP/AMFI settings and use the overlay chain.
4. Validate the installed Tahoe desktop and restart, AppleParavirtGPU/Metal,
   Finder/Dock/Safari, WindowServer/kernel logs and Liquid Glass screenshots.
   Compare METAL_ERROR_MODE only if the observed assertions require it.
5. Use an active animation workload with benchmark.ps1; static or paused
   present counts are not FPS evidence. Compare exact rendering with
   REIMS_VGPU_EXACT=all, resolutions and cold/warm cache conditions. Add
   hardware timestamp and shader/cache/lock profiling before claiming GPU
   render duration or 1% low performance.
6. Test guest-page release/reuse, sustained GPU memory use and crash/reset
   recovery on the actual guest. Keep the remaining 32 GiB Vec case and full
   GPU/Mac suite limitations explicit until their checks can run correctly.

See windows-vm.md for stop, snapshot create/restore, log collection and
reproducible preparation. Current private artifacts and prepared snapshot
are retained under vm/. All three owned forks use windows-native-tahoe;
master and older branches are preserved.
