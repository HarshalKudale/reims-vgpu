# Windows VM preparation and management

These scripts prepare one x86_64 macOS VM in `vm/` using native Windows
PowerShell, Python, 7-Zip and QEMU tools. They use the project's patched QEMU
with `apple-gfx-pci`, its `ReimsVgpu.rom`, and WHPX. Defaults are 8 vCPUs,
8 GiB RAM, a sparse 128 GiB qcow2 disk, and one 1920×1080 display.

The Windows Rust/QEMU build and package setup are separate. Preparation does
not prove a Windows guest boot or Vulkan rendering works. A normal start
requires an enabled Windows Hypervisor Platform and a running hypervisor;
there is no automatic TCG fallback.

## Fluent Windows manager

`build/windows-manager/ReimsManager.exe` uses WPF's built-in Windows Fluent
theme and follows the system light/dark setting. Keep the whole published
folder: it contains the .NET runtime and the PowerShell backend. The app
selects a project folder, then manages its existing `vm/state` configuration.
It does not create a second set of disks behind the CLI's back.

Build it with a Windows .NET 10 SDK:

```powershell
./scripts/windows/build-manager.ps1 -Dotnet <path-to-dotnet.exe> -SelfTest
```

The setup tab selects an ISO, prepares a sparse disk and validated OpenCore,
and generates a private machine identity once. Existing disks and NVRAM are
retained. The hardware page edits CPU cores, RAM, installer attachment,
NAT/TAP networking, audio and display resolution. Disk expansion creates a
larger child overlay, preserving the previous disk; grow the APFS partition
inside macOS afterwards. Disks are never shrunk.

Power-off retains QEMU; Start resets and powers on that same process with
unchanged launch settings. Complete Exit waits for macOS to shut down and
then closes QEMU, allowing offline settings and snapshots. Restart asks
macOS to reboot. Pause/Resume use QMP. The explicit force-exit action warns
that unsaved guest work is lost. Closing the manager itself leaves the VM
running.

After installing macOS, open `REIMSTOOLS` in Finder and run `setup.command`.
It installs the host's SSH public key, enables the built-in SSH service, sets
Japanese keyboard/timezone preferences and the measured Metal preference,
and permits only the exact shutdown/restart commands through passwordless
sudo. The guest password is entered in macOS and is never stored by the
manager. Enter the displayed SHA256 host-key fingerprint and guest user in
the connection tab. Pairing rejects a different fingerprint. `REIMSTOOLS`
is a generated SATA FAT disk under a disposable overlay; it contains only
authored scripts and the public key, not guest or Apple binaries.

NAT is the default and forwards SSH only on loopback. Bridge mode passes an
existing TAP-Windows adapter name to QEMU and uses the guest's LAN address
for SSH, with the same pinned host key. Wintun and VMware adapters cannot
substitute for a TAP device. The bridge-preparation page installs a locally
selected, valid OpenVPN-signed TAP installer and calls Windows `netsh bridge
create` for the explicitly selected TAP and physical adapter. Those two
host operations request Windows elevation. Bridge creation can change the
host's address and briefly interrupt networking. No TAP driver or physical
bridge is silently installed when NAT is selected.

The display offers 720p, 1080p, 1440p and 4K at 60 Hz. macOS may restore its
own saved mode after boot. The live resolution action applies and saves a
Core Graphics display configuration through pinned SSH, so the mode does
not revert when the helper exits. 1080p is the default; a successfully
advertised 4K mode is not a performance guarantee.

`prepare-opencore.ps1 -GenerateIdentity -Rebuild` uses the official release's
macserial for a new serial/MLB pair, takes ROM from this VM's unicast MAC,
and preserves the installed SystemUUID and Mac model. Values and backups
remain in ignored private state. Repeated setup retains this identity.
This prepares SMBIOS; only an actual sign-in can establish that Apple
Account services accept it. The app does not collect Apple credentials.

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
x86legacy Apple Secure Boot model and signed DMG loading are configured; CSR is
zero, and no AMFI disabling boot arguments are set. Sample serial/MLB values
are placeholders; this setup does not provision Apple online services.

OpenCore documents `x86legacy` for VMs. On the measured Tahoe 26.4 installer,
`j185` booted recovery but selected a board-22 sealing manifest, while the
user-space software verifier required board f0. Its kernel-only
`ForceSecureBootScheme` quirk did not fix that mismatch. `x86legacy` selected
the matching manifest and passed board and digest verification. Existing
plists are preserved: change `Misc/Security/SecureBootModel` to `x86legacy`
and `Kernel/Quirks/ForceSecureBootScheme` to false while QEMU is exited, then
run preparation with `-Rebuild`. Preserve disk and firmware checkpoints when
changing personalization. See the
[OpenCore manual](https://github.com/acidanthera/OpenCorePkg/blob/1.0.8/Docs/Configuration.tex).

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

Normal launches retain WHPX's kernel interrupt controller. Reset now clears
the native MTRRs as x86 CPU reset does: leaving their fixed-range enable bit
set caused OVMF's `MemDetect.c` assertion on warm boot. XSAVE buffer size is
negotiated with WHP, and reset writes the initial extended registers even
while OSXSAVE is off. The eight-CPU reset returns to OpenCore with the same
process. Runtime VP delete/create is excluded after an experimental run
coincided with a host `HYPERVISOR_ERROR`.

The picker waits for an explicit selection during installation. Serial
kernel diagnostics are enabled without relaxing SIP or AMFI. After boot,
recovery reports SIP enabled; OpenCore's temporary booter CSR bit for slide
selection is restored before XNU receives it.

The current VM uses `x86legacy`, with ForceSecureBootScheme false. Its
software IMG4 scheme matches the installer manifest. The earlier j185
experiment confirmed that the kernel quirk alone does not change the
user-space sealing verifier; its MSU 1130 failure was resolved by selecting
the VM model, with signature verification still enforced.

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
as GPT/APFS and recovery reports 26.4/25E246 with SIP enabled.

On 2026-10-13, RELEASE OpenCore with `x86legacy` completed sealing and
booted the installed 26.4 desktop. Finder, Dock, Safari and Settings drew
successfully. The guest reported the Apple Paravirtualized Graphics Device
and Metal 2. A 3840x2160 framebuffer with a 1920x1080 logical desktop was
observed, but interaction slowed at 4K and the working default was restored
to 1080p. These observations do not establish a 60 FPS workload.

The window's 92 tests, the native HID report checks and the Windows
management/overlay checks passed. The full check's formatting, clippy,
header and doctest stages ran, but its test run remains incomplete on
Windows: the unchanged C integration harness includes `sys/mman.h`. It is
not reported as a green full suite. Bridge networking still needs a host
with a configured TAP bridge for physical-network validation.
