# Continuation

Finish the Windows builds and tests, integrate the independent worker commits,
prepare OpenCore and the VM, then verify device realization and explicit WHPX
failure without a TCG fallback.

At a safe checkpoint, enable Windows Hypervisor Platform from an administrator
PowerShell with `scripts/windows/enable-whpx.ps1`, save other work and restart
Windows. Run `scripts/windows/doctor.ps1 -RequireWhpx` afterwards, then boot the
prepared VM. The macOS installer agreement and account setup need the user's
own input. Validate Tahoe rendering and performance on the resulting desktop.
