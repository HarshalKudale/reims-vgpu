# Windows VM preparation and management

These scripts prepare one x86_64 macOS VM in `vm/` using native Windows
PowerShell, Python, 7-Zip and QEMU tools. They use the project's patched QEMU
with `apple-gfx-pci`, its `ReimsVgpu.rom`, and WHPX. Defaults are 8 vCPUs,
8 GiB RAM, a sparse 128 GiB qcow2 disk, and one 1920×1080 display.

The Windows Rust/QEMU build and package setup are separate. Preparation does
not prove a Windows guest boot or Vulkan rendering works. A normal start
requires an enabled Windows Hypervisor Platform and a running hypervisor;
there is no automatic TCG fallback.

## Licensing

Bring your own legitimately obtained installer and read the license that
accompanies it. Apple's current [macOS Tahoe agreement](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf),
section 2B(iii), permits up to two additional virtual instances on an
Apple-branded computer you own or control that is already running the Apple
software, for the purposes listed there. Section 2J excludes installing,
using or running it on a non-Apple-branded computer. These Windows scripts do
not grant permission to run macOS on ordinary PC hardware. The
[Apple license index](https://www.apple.com/legal/sla/) explains that the
license accompanying your copy may differ from the online text. No script
accepts a license, enters credentials, or disables SIP or AMFI.

## Required inputs

- PowerShell 7.2 or newer and Windows Python 3 on PATH.
- Native `7z.exe`, `qemu-img.exe`, and, for the self-checks, `qemu-io.exe`.
  A native MSYS2 QEMU package supplies the latter two and OVMF. The environment
  helper supplies its MSYS2 root; scripts also accept explicit tool paths.
- The build's `build/qemu/qemu-system-x86_64.exe` and
  `.work/target/dist-vulkan/share/reims-vgpu/ReimsVgpu.rom`. `start.ps1 -Qemu <path>` selects
  another build. A stock QEMU lacking the reims device is refused.
- A matched QEMU firmware pair: `edk2-x86_64-code.fd` and
  `edk2-i386-vars.fd`. Despite the variables file's name, this is the pair
  shipped for QEMU's x86_64 OVMF. The code and variables must come from the
  same package.
- Your installer image, supplied with `-Iso`; its path is remembered in the
  ignored `vm/state/media.json`. No host-specific ISO path is committed.

All scripts dot-source `scripts/windows/environment.ps1`, which keeps temp,
caches, downloads and outputs under the project. `REIMS_PROJECT_ROOT_OVERRIDE`
lets a worktree's scripts operate on the owner's project artifacts during
testing. It affects the artifact location, not the source checkout.

## Prepare without starting a guest

Run from the repository root in PowerShell:

```powershell
./scripts/windows/prepare-vm.ps1 -Iso '<your installer path>' -InspectOnly -HashIso
./scripts/windows/prepare-opencore.ps1
./scripts/windows/prepare-vm.ps1
./scripts/windows/start.ps1 -DryRun
```

If automatic tool or firmware discovery does not find your package:

```powershell
./scripts/windows/prepare-opencore.ps1 -QemuImg '<qemu-img.exe>' -FirmwareDirectory '<QEMU share/qemu>'
./scripts/windows/prepare-vm.ps1 -Iso '<your installer path>' -SevenZip '<7z.exe>' -QemuImg '<qemu-img.exe>'
```

Inspection reads the image header and uses 7-Zip to list its contents and
extract only `SystemVersion.plist` and `boot.efi` to `vm/media/inspection/`.
It validates the booter's x86_64 PE machine type and records the product
version/build and original size/mtime. `-HashIso` additionally records the
whole original's SHA256; subsequent inspections retain it when the path,
size and mtime agree. Neither the original nor the installer payload is
rewritten. A file named `.iso` whose header is ER/PM is an APM/HFS+ disk,
not an ISO9660 CD, and is attached accordingly.

OpenCore is pinned to the official [OpenCorePkg 1.0.8 release](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8).
`-Version` can select another official release with a GitHub SHA256 asset
digest. Downloads live in `.work/downloads/`. The script verifies that
digest, derives its plist from that release's Sample.plist, and runs the
same release's Windows `ocvalidate.exe`. Once cached, it needs no network.
It uses `OpenRuntime.efi`, `OpenPartitionDxe.efi` for Apple partition maps,
and the open source `OpenHfsPlus.efi`, with no
Apple firmware or kext binaries added. The built-in picker, iMac20,1 model,
j185 Apple Secure Boot model and signed DMG loading are configured; CSR is
zero, and no AMFI disabling boot arguments are set. Sample serial/MLB values
are placeholders; this setup does not provision Apple online services.

Native `qemu-img convert -f vvfat` makes a sparse FAT16 image from the EFI
directory, then its MBR partition type is marked as an EFI System Partition.
OVMF code and an untouched variables template are copied into `vm/firmware/`.
The working NVRAM is a separate copy. Re-running preparation preserves the
VM's existing disk, NVRAM and settings. An edited OpenCore plist/image needs
`prepare-opencore.ps1 -Rebuild`; validation runs before replacing its image.
That is a firmware change and intentionally prevents restoring snapshots
made with a different firmware image.

`vm/disks/base.qcow2` is an independent, empty 128 GiB image. The VM writes
`current.qcow2`, an overlay of that base, or an overlay created by snapshots.
The launcher refuses a base disk used directly and checks its backing chain.
OpenCore and an APM installer use temporary `snapshot=on` overlays, whose
files stay in the project's TEMP directory. QEMU's IDE HDD implementation
refuses `readonly=on`, so these overlays protect the originals while giving
the guest a writable IDE device. An ISO9660 installer uses a read-only CD.

## Start and stop

An administrator can enable Windows Hypervisor Platform and reboot in a
separate elevated Windows session. The scripts neither elevate nor change
host boot configuration:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
```

Before a guest boot, stop competing GPU tests/builds as required by
[the boot discipline](qemu.md#booting-a-guest-to-check-a-change). Then:

```powershell
./scripts/windows/start.ps1
./scripts/windows/stop.ps1                      # guest power-off; keep QEMU
./scripts/windows/start.ps1                     # power on the same process
./scripts/windows/stop.ps1 -Exit                # clean shutdown and exit QEMU
./scripts/windows/start.ps1 -WithoutInstaller     # after installation
./scripts/windows/stop.ps1 -Force                # discard unsaved work and exit QEMU
```

Normal launches use `-no-shutdown`: a guest restart stays in QEMU, and a
guest power-off leaves QMP available in the `shutdown` state. `start.ps1`
resets that powered-off machine and resumes its CPUs in the same process.
It refuses to restart a running or paused guest, or silently reuse different
launch settings. Use `qmp.ps1 -Command cont` to resume an intentional pause.
Use `stop.ps1 -Exit` before changing attached disks, firmware, launch options
or the QEMU executable, and before an offline snapshot. The powered-off
process still holds its disks open.

The guest installer and Setup Assistant remain interactive. Scripts do not
accept agreements, enter passwords, alter guest security, or automate an
installation. OpenCore validation is a schema check, not a boot check. The
Haswell CPU model and its required AVX/AVX2/XSAVE flags use `enforce`, so an
unsupported accelerator/CPU combination fails rather than hiding missing
features. Native WHPX recovery boot is recorded below; the installed system
and its GPU workload still need verification.

WHPX on the measured Windows host does not expose CPUID leaf 6's ARAT bit.
The default Haswell model masks that bit with `-arat`, retaining `enforce`
for its other required features. It also selects `stepping=3`: QEMU's
default Haswell stepping 1 reaches XNU's rejection of pre-C0 processors.
An existing VM's `vm/state/config.json` retains its settings; add
`,stepping=3` after `Haswell-noTSX` and `,-arat` before `,enforce` in its CPU
string.

The picker waits for an explicit selection during installation. Serial
kernel diagnostics are enabled without relaxing SIP or AMFI. After boot,
recovery reports SIP enabled; OpenCore's temporary booter CSR bit for slide
selection is restored before XNU receives it.

Its `-L` path points to the pinned QEMU source's `pc-bios`, so relocating the
executable does not lose its network/virtual APIC option ROMs.
The command retains the existing q35 PCI layout: AHCI at slot 2, network at
3, `apple-gfx-pci` at 4 and xHCI at 5. It uses the real `displays`,
`resolution` and `romfile` properties. Keyboard/tablet and a USB audio output
device use xHCI. The audio backend is `none`, as in the project's measured
headless configuration, so samples are discarded. QEMU's own display is
disabled; the library owns the normal display window. `-Headless` suppresses
that window. `-Paused` realizes devices under WHPX without executing CPUs.

QMP listens only on `127.0.0.1:4444`, and guest SSH forwards only from
`127.0.0.1:2222`; no password or SSH daemon is configured automatically.
`prepare-vm.ps1 -QmpPort/-SshPort` chooses ports when creating a new VM.
QMP is unauthenticated, so local processes with access to its port can
control the guest. The management scripts check the recorded PID's start
time and executable before connecting or stopping it, refusing PID reuse.

## Operate the VM from the CLI

`qmp.ps1` uses the same recorded-process and localhost checks. Pass a QMP
command and a PowerShell hashtable; it returns the command's result as JSON.
No desktop automation or foreground window is needed:

```powershell
./scripts/windows/qmp.ps1 -Command query-status
./scripts/windows/qmp.ps1 -Command query-block
./scripts/windows/qmp.ps1 -Command stop            # pause CPUs
./scripts/windows/qmp.ps1 -Command cont            # resume CPUs
./scripts/windows/qmp.ps1 -Command system_reset    # hard reset in this process
./scripts/windows/qmp.ps1 -Command send-key -Arguments @{ keys = @(@{ type = 'qcode'; data = 'ret' }); 'hold-time' = 100 }
./scripts/windows/qmp.ps1 -Command screendump -Arguments @{ filename = 'D:/git/reims/vm/logs/guest.ppm' }
```

For mouse input, `input-send-event` accepts absolute coordinates from 0 to
32767 on each axis and separate button press/release events. This moves to
the centre and clicks the left button:

```powershell
./scripts/windows/qmp.ps1 -Command input-send-event -Arguments @{ events = @(
    @{ type = 'abs'; data = @{ axis = 'x'; value = 16384 } }
    @{ type = 'abs'; data = @{ axis = 'y'; value = 16384 } }
    @{ type = 'btn'; data = @{ button = 'left'; down = $true } }
) }
Start-Sleep -Milliseconds 150
./scripts/windows/qmp.ps1 -Command input-send-event -Arguments @{ events = @(
    @{ type = 'btn'; data = @{ button = 'left'; down = $false } }
) }
```

Inspect a fresh guest screendump before selecting keys or coordinates.
Screen capture defaults to PPM, so it also works without QEMU's optional
libpng support. Use `stop.ps1` for a normal shutdown; `system_reset` is a
hard reset and can discard unsaved guest work. Handle agreements and account
credentials personally.

`-DiagnosticTcg` is an explicit **paused device diagnostic**. It
always includes `-S`; it is not a boot or performance result. The benchmark
refuses it. Add `-Headless` to suppress its window. Nothing switches a normal
start to this mode automatically.

## Offline snapshots, logs and measurements

```powershell
./scripts/windows/snapshot.ps1 -Action Create -Name before-install
./scripts/windows/snapshot.ps1 -Action List
./scripts/windows/snapshot.ps1 -Action Restore -Name before-install
./scripts/windows/collect-logs.ps1 -Screenshot -Zip
./scripts/windows/benchmark.ps1 -Seconds 60
```

Create/Restore require a stopped VM. A snapshot freezes the current disk by
making the next active disk its child, and saves a copy of NVRAM. Restore
creates another overlay and NVRAM copy, leaving existing disks intact.
These are disk/NVRAM snapshots, not RAM or running-process snapshots. They
reject changed OVMF/OpenCore hashes and never delete or overwrite a named
snapshot. Keep the backing chain; removing a parent loses its children.

Each start records its exact argument array, WHPX preflight, stdout/stderr,
serial output and QMP status in `vm/logs/`. Collection writes a local
`.work/diagnostics/vm-*` report with host/driver details and matched fatal
lines. `-Screenshot` uses QMP's guest `screendump`, never the host screen;
a stopped VM or a QMP failure is recorded instead of faking an image.
Reports and ZIPs may contain guest details and host paths. Review them before
sharing; they are not committed or uploaded by these scripts.

The benchmark samples only the recorded running WHPX process's CPU and
memory during your workload. It also preserves `REIMS_VGPU_STATS` lines
emitted during that interval: guest presents, window draws and window GPU
times. A missing stats interval is recorded as missing evidence. It does
not manufacture an FPS score or prove a correct desktop. An optional
`-GuestUser <name> -IdentityFile <key>` performs read-only macOS/CPU/display
inventory using an existing SSH key and `vm/state/known_hosts`, with batch
mode and strict host-key checking. It will fail if that setup is absent.

For final boot validation, collect a real guest screendump and check the
Dock, wallpaper, menu bar and a fixed alert; fail any `reims-vgpu: fatal`
line. Guest apps and GPU workloads need their own measurements after boot.

## Self-checks and observed preparation

```powershell
./scripts/windows/tests/firmware-vm.ps1
./scripts/windows/tests/firmware-vm.ps1 -PreparedArtifactsRoot (Get-Location).Path
```

On a separate worktree before the environment helper is merged, pass
`-EnvironmentScript <the supplied environment.ps1>`; this only copies that
helper into the test's temporary script directory. Tests create their own
sparse disks and a loopback Python QMP fixture under `.work/tmp/`, then
remove those artifacts. They check actual overlay data and NVRAM restoration,
PID reuse refusal, event/response matching, error handling, Windows native
argument quoting, media header/architecture refusals, localhost arguments,
guest screendump collection, and absent benchmark frame evidence. They use
no VM or GPU. The optional artifact checks additionally run the prepared
release's ocvalidate, inspect the generated FAT image with 7-Zip and check
the real sparse disk.

Preparation observed on 2026-10-12 with native 7-Zip 25.01 and qemu-img
11.0.3: the supplied 20,971,520,000-byte ER/PM APM/HFS+ image contains macOS
26.4, build 25E246, and an x86_64 PE booter. OpenCore 1.0.8's official asset
digest matched, and ocvalidate reported no issues. Exact original/image
hashes, commands and results remain in the ignored `vm/state/` and
`.work/diagnostics/firmware-vm/` records. Windows Hypervisor Platform was
disabled (InstallState 2) and HypervisorPresent was false. No guest boot,
installation, desktop correctness or Windows guest GPU performance has
been demonstrated by that preparation. After the host restart, WHPX reports
a running hypervisor. Masking ARAT allows the enforced Haswell model to
start; adding OpenPartitionDxe makes the APM/HFS+ installer visible. CLI
input starts the Tahoe booter, which verifies the j185 kernel collection
and boots the recovery UI. The core/thread count MSR must reflect eight
CPUs, rather than leaving XNU's one-CPU fallback. The new target was formatted
as GPT/APFS and recovery reports 26.4/25E246 with SIP enabled. Installation,
guest Metal and the desktop remain unverified.
