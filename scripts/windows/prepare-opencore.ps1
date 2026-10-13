#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '1.0.8',
    [string]$QemuImg,
    [string]$FirmwareDirectory,
    [switch]$Rebuild
)
. "$PSScriptRoot/start.ps1" -FunctionsOnly
Assert-ReimsVmStopped
$downloads = Join-Path $ProjectRoot '.work/downloads'
$releasePath = Join-Path $downloads "OpenCore-$Version-release.json"
if (!(Test-Path -LiteralPath $releasePath)) {
    $release = Invoke-RestMethod "https://api.github.com/repos/acidanthera/OpenCorePkg/releases/tags/$Version" -Headers @{ 'User-Agent' = 'reims-windows-setup' }
    Write-ReimsJson $releasePath $release
} else { $release = Get-Content -Raw -LiteralPath $releasePath | ConvertFrom-Json }
$asset = $release.assets | Where-Object name -EQ "OpenCore-$Version-RELEASE.zip"
if (!$asset -or $asset.digest -notmatch '^sha256:([a-f0-9]{64})$') { throw 'Official release has no SHA256 asset digest.' }
$expectedHash = $Matches[1]
$url = "https://github.com/acidanthera/OpenCorePkg/releases/download/$Version/OpenCore-$Version-RELEASE.zip"
if ($asset.browser_download_url -ne $url) { throw 'Unexpected OpenCore asset URL.' }
$archive = Join-Path $downloads $asset.name
if (!(Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest $url -OutFile "$archive.partial"
    if ((Get-FileHash -LiteralPath "$archive.partial" -Algorithm SHA256).Hash -ne $expectedHash) { throw 'OpenCore download digest mismatch.' }
    Move-Item -LiteralPath "$archive.partial" -Destination $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Cached OpenCore digest mismatch.' }
$package = Join-Path $downloads "OpenCore-$Version"
if (!(Test-Path -LiteralPath (Join-Path $package 'Docs/Sample.plist'))) { Expand-Archive -LiteralPath $archive -DestinationPath $package -Force }
$QemuImg = Get-ReimsTool 'qemu-img.exe' $QemuImg
$python = Get-ReimsTool 'python.exe'
$destination = Join-Path $ProjectRoot "vm/firmware/opencore-$Version"
$efiRoot = Join-Path $destination 'root'
New-Item -ItemType Directory -Force -Path (Join-Path $efiRoot 'EFI/BOOT'), (Join-Path $efiRoot 'EFI/OC/Drivers') | Out-Null
foreach ($relative in @('BOOT/BOOTx64.efi', 'OC/OpenCore.efi', 'OC/Drivers/OpenRuntime.efi', 'OC/Drivers/OpenPartitionDxe.efi', 'OC/Drivers/OpenHfsPlus.efi')) {
    Copy-Item -LiteralPath (Join-Path $package "X64/EFI/$relative") -Destination (Join-Path $efiRoot "EFI/$relative") -Force
}
$plist = Join-Path $efiRoot 'EFI/OC/config.plist'
if (!(Test-Path -LiteralPath $plist)) {
    $script = @'
import copy, pathlib, plistlib, sys, uuid
source, target = map(pathlib.Path, sys.argv[1:])
c = plistlib.loads(source.read_bytes())
for section, keys in {'ACPI': ('Add','Delete','Patch'), 'Booter': ('MmioWhitelist','Patch'),
                      'Kernel': ('Add','Block','Force','Patch'), 'Misc': ('Entries','Tools')}.items():
    for key in keys:
        c[section][key] = []
c['DeviceProperties']['Add'] = {}
c['DeviceProperties']['Delete'] = {}
c['Booter']['Quirks'].update(EnableWriteUnprotector=False, RebuildAppleMemoryMap=True, SyncRuntimePermissions=True)
c['Kernel']['Emulate']['DummyPowerManagement'] = True
c['Kernel']['Quirks'].update(AppleXcpmExtraMsrs=True, DisableLinkeditJettison=False, ForceSecureBootScheme=False)
c['Misc']['Boot'].update(HideAuxiliary=False, Timeout=0)
c['Misc']['Debug'].update(AppleDebug=True, ApplePanic=True, DisplayLevel=0x80000042, Target=75)
c['Misc']['Serial']['Init'] = True
c['Misc']['Security'].update(ScanPolicy=0, SecureBootModel='x86legacy', DmgLoading='Signed', Vault='Optional')
apple = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
c['NVRAM']['Add'][apple] = {'boot-args': '-v keepsyms=1 serial=3 debug=0x108', 'csr-active-config': bytes(4),
                          'prev-lang:kbd': b'en:252', 'run-efi-updater': 'No'}
c['NVRAM']['Delete'][apple] = ['boot-args']
generic = c['PlatformInfo']['Generic']
generic.update(SystemProductName='iMac20,1', SystemUUID=str(uuid.uuid4()).upper(),
               ROM=b'\x02\x52\x45\x49\x4d\x53')
driver = next(x for x in c['UEFI']['Drivers'] if x['Path'] == 'OpenRuntime.efi')
hfs = copy.deepcopy(driver)
hfs['Path'], hfs['Comment'] = 'OpenHfsPlus.efi', 'OpenCore HFS+ driver'
partition = copy.deepcopy(driver)
partition['Path'], partition['Comment'] = 'OpenPartitionDxe.efi', 'Apple partition map support'
c['UEFI']['Drivers'] = [driver, partition, hfs]
c['UEFI']['Output']['Resolution'] = '1920x1080'
target.write_bytes(plistlib.dumps(c, sort_keys=False))
'@
    $script | & $python - (Join-Path $package 'Docs/Sample.plist') $plist
    if ($LASTEXITCODE -ne 0) { throw 'OpenCore configuration generation failed.' }
}
$validate = Join-Path $package 'Utilities/ocvalidate/ocvalidate.exe'
$validation = Invoke-ReimsTool $validate @($plist)
$validation | Set-Content -LiteralPath (Join-Path $destination 'ocvalidate.log') -Encoding utf8NoBOM
$image = Join-Path $destination 'OpenCore.img'
$configHash = (Get-FileHash -LiteralPath $plist).Hash
$manifestPath = Join-Path $ProjectRoot 'vm/state/opencore.json'
if (!$Rebuild -and (Test-Path -LiteralPath $image) -and (Test-Path -LiteralPath $manifestPath)) {
    $previous = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($previous.image -eq $image -and ($previous.config_sha256 -ne $configHash -or
        $previous.image_sha256 -ne (Get-FileHash -LiteralPath $image).Hash)) {
        throw 'OpenCore config or image changed. Use -Rebuild to validate and rebuild its EFI image.'
    }
}
if ($Rebuild -or !(Test-Path -LiteralPath $image)) {
    Invoke-ReimsTool $QemuImg @('convert', '-f', 'vvfat', '-O', 'raw', ('fat:' + $efiRoot.Replace('\', '/')), "$image.partial")
    $stream = [IO.File]::Open("$image.partial", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    try {
        [void]$stream.Seek(510, [IO.SeekOrigin]::Begin)
        if ($stream.ReadByte() -ne 0x55 -or $stream.ReadByte() -ne 0xaa) { throw 'vvfat did not produce an MBR.' }
        [void]$stream.Seek(450, [IO.SeekOrigin]::Begin)
        $stream.WriteByte(0xef) # Mark vvfat's FAT partition as an EFI System Partition.
    } finally { $stream.Dispose() }
    Move-Item -LiteralPath "$image.partial" -Destination $image -Force
}
if (!$FirmwareDirectory) {
    $candidates = @((Join-Path $MsysRoot 'ucrt64/share/qemu'), (Join-Path $MsysRoot 'mingw64/share/qemu'), (Join-Path $ProjectRoot 'build/qemu/pc-bios'))
    $FirmwareDirectory = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'edk2-x86_64-code.fd') } | Select-Object -First 1
}
if (!$FirmwareDirectory) { throw 'Pass -FirmwareDirectory from a native QEMU package with x86_64 OVMF code and variables.' }
$codeSource = Join-Path $FirmwareDirectory 'edk2-x86_64-code.fd'
$varsSource = Join-Path $FirmwareDirectory 'edk2-i386-vars.fd'
foreach ($source in @($codeSource, $varsSource)) {
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Incomplete OVMF pair: $source" }
}
$firmware = Join-Path $ProjectRoot 'vm/firmware'
$code = Join-Path $firmware 'OVMF_CODE.fd'
$varsTemplate = Join-Path $firmware 'OVMF_VARS.template.fd'
foreach ($pair in @(@($codeSource, $code), @($varsSource, $varsTemplate))) {
    if (Test-Path -LiteralPath $pair[1]) {
        if ((Get-FileHash -LiteralPath $pair[0]).Hash -ne (Get-FileHash -LiteralPath $pair[1]).Hash) {
            throw "Existing firmware differs from this package: $($pair[1]). Keep a matched code/variables pair."
        }
    } else { Copy-Item -LiteralPath $pair[0] -Destination $pair[1] }
}
$manifest = [ordered]@{
    schema = 1; version = $Version; release_url = $url; release_sha256 = $expectedHash
    image = $image; image_sha256 = (Get-FileHash -LiteralPath $image).Hash
    config = $plist; config_sha256 = $configHash
    ocvalidate = $validate; firmware_code = $code; firmware_vars_template = $varsTemplate
    code_sha256 = (Get-FileHash -LiteralPath $code).Hash; vars_sha256 = (Get-FileHash -LiteralPath $varsTemplate).Hash
    firmware_source = $FirmwareDirectory; validated = $true
}
Write-ReimsJson $manifestPath $manifest
$manifest | ConvertTo-Json -Depth 5
