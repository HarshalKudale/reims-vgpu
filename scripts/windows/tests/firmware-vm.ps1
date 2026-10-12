#Requires -Version 7.2
[CmdletBinding()]
param([string]$EnvironmentScript, [string]$QemuImg, [string]$QemuIo, [string]$PreparedArtifactsRoot)
$ErrorActionPreference = 'Stop'
$sourceScripts = Split-Path $PSScriptRoot
if (!$EnvironmentScript) { $EnvironmentScript = Join-Path $sourceScripts 'environment.ps1' }
. $EnvironmentScript
$artifactRoot = $ProjectRoot
$testRoot = Join-Path $ProjectRoot ('.work/tmp/windows-vm-test ' + [guid]::NewGuid().ToString())
$testScripts = Join-Path $testRoot 'scripts/windows'
New-Item -ItemType Directory -Force -Path $testScripts | Out-Null
Copy-Item -Path (Join-Path $sourceScripts '*.ps1') -Destination $testScripts
Copy-Item -LiteralPath $EnvironmentScript -Destination (Join-Path $testScripts 'environment.ps1') -Force
$oldOverride = $env:REIMS_PROJECT_ROOT_OVERRIDE
$env:REIMS_PROJECT_ROOT_OVERRIDE = $testRoot
. (Join-Path $testScripts 'start.ps1') -FunctionsOnly
$script:assertions = 0
function Assert-Condition($Condition, [string]$Message) {
    if (!$Condition) { throw "ASSERT: $Message" }
    $script:assertions++
}
function Assert-Throws([scriptblock]$Operation, [string]$Pattern) {
    $caught = $false
    try { & $Operation | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $caught = $true
    }
    Assert-Condition $caught "Expected refusal: $Pattern"
}
$mock = $null
try {
    foreach ($file in Get-ChildItem -LiteralPath $sourceScripts -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert-Condition ($errors.Count -eq 0) "$($file.Name) must parse"
    }
    Assert-Throws { Assert-ReimsArtifactPath (Join-Path $testRoot '../outside.txt') } 'Artifact must stay'
    $QemuImg = Get-ReimsTool 'qemu-img.exe' $QemuImg
    $QemuIo = Get-ReimsTool 'qemu-io.exe' $QemuIo
    $python = Get-ReimsTool 'python.exe'
    $diskDirectory = Join-Path $testRoot 'vm/disks'
    $firmwareDirectory = Join-Path $testRoot 'vm/firmware'
    New-Item -ItemType Directory -Force -Path $diskDirectory, $firmwareDirectory | Out-Null
    $base = Join-Path $diskDirectory 'base.qcow2'
    $active = Join-Path $diskDirectory 'current.qcow2'
    Invoke-ReimsTool $QemuImg @('create', '-f', 'qcow2', $base, '128G') | Out-Null
    Invoke-ReimsTool $QemuImg @('create', '-f', 'qcow2', '-F', 'qcow2', '-b', $base, $active) | Out-Null
    Invoke-ReimsTool $QemuIo @('-f', 'qcow2', '-c', 'write -P 0x7a 0 512', $active) | Out-Null
    $baseHash = (Get-FileHash -LiteralPath $base).Hash
    $code = Join-Path $firmwareDirectory 'code.fd'
    $vars = Join-Path $firmwareDirectory 'vars.fd'
    $oc = Join-Path $firmwareDirectory 'opencore.img'
    'firmware' | Set-Content -LiteralPath $code, $vars, $oc
    $config = [pscustomobject]@{
        schema = 1; cpus = 8; memory_mib = 8192; resolution = '1920x1080'; disk_gib = 128
        cpu = 'Haswell-noTSX,enforce'; mac = '52:54:00:01:02:03'; qmp_port = 4444; ssh_port = 2222
        iso = Join-Path $testRoot 'original installer.iso'; media_kind = 'disk'; base_disk = $base; active_disk = $active
        opencore = $oc; firmware_code = $code; firmware_vars = $vars; rom = Join-Path $firmwareDirectory 'ReimsVgpu.rom'
    }
    Write-ReimsJson (Join-Path $testRoot 'vm/state/config.json') $config
    $badConfig = $config.PSObject.Copy()
    $badConfig.active_disk = $base
    Write-ReimsJson (Join-Path $testRoot 'vm/state/config.json') $badConfig
    Assert-Throws { Get-ReimsVmConfig } 'base disk directly'
    Write-ReimsJson (Join-Path $testRoot 'vm/state/config.json') $config
    $command = Get-ReimsQemuArguments $config (Join-Path $testRoot 'vm/logs/test')
    Assert-Condition ($command[$command.IndexOf('-accel') + 1] -eq 'whpx') 'WHPX is the sole default accelerator'
    Assert-Condition ('tcg' -notin $command) 'No automatic TCG fallback'
    Assert-Condition (($command | Where-Object { $_ -like 'id=installer,*' }) -match 'snapshot=on') 'APM original is protected by an overlay'
    Assert-Condition (($command | Where-Object { $_ -like 'id=opencore,*' }) -match 'snapshot=on') 'OpenCore template is protected by an overlay'
    Assert-Condition (($command -join ' ') -match 'apple-gfx-pci.*resolution=1920x1080') 'Actual GPU ABI and 1080p'
    Assert-Condition (($command -join ' ') -match 'tcp:127.0.0.1:4444' -and ($command -join ' ') -match 'hostfwd=tcp:127.0.0.1:2222') 'QMP and SSH stay on localhost'
    $diagnostic = Get-ReimsQemuArguments $config $testRoot -DiagnosticTcg
    Assert-Condition ('tcg' -in $diagnostic -and '-S' -in $diagnostic) 'Explicit TCG diagnostics remain paused'
    $config.media_kind = 'cdrom'
    $cd = Get-ReimsQemuArguments $config $testRoot
    Assert-Condition (($cd | Where-Object { $_ -like 'id=installer,*' }) -match 'media=cdrom,readonly=on') 'ISO9660 is a read-only CD'
    Assert-Condition (!(Get-ReimsQemuArguments $config $testRoot -WithoutInstaller | Where-Object { $_ -like 'id=installer,*' })) 'Installer can be ejected at the next boot'
    Assert-Condition ((ConvertTo-ReimsQemuPath 'x:\comma,path\file') -eq 'x:/comma,,path/file') 'QEMU paths escape commas'

    # Execute the media parser from the script against synthetic, non-Apple inputs.
    $mediaAst = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $sourceScripts 'prepare-vm.ps1'))).Ast
    $mediaParser = $mediaAst.Find({ param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value.StartsWith('import json, pathlib, plistlib, struct, sys')
    }, $true).Value
    $fixtureDirectory = Join-Path $testRoot 'media-fixture'
    New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
    $fixtureSetup = @'
import pathlib, plistlib, struct, sys
r=pathlib.Path(sys.argv[1])
image=bytearray(32775)
image[:2]=b'ER'; image[512:514]=b'PM'
(r/'media.iso').write_bytes(image)
efi=bytearray(256); efi[:2]=b'MZ'; struct.pack_into('<I',efi,0x3c,128)
efi[128:132]=b'PE\0\0'; struct.pack_into('<H',efi,132,0x8664)
(r/'boot.efi').write_bytes(efi)
(r/'SystemVersion.plist').write_bytes(plistlib.dumps({'ProductVersion':'test','ProductBuildVersion':'fixture'}))
'@
    $fixtureSetup | & $python - $fixtureDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Media fixture setup failed.' }
    $parsed = $mediaParser | & $python - (Join-Path $fixtureDirectory 'media.iso') $fixtureDirectory | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -eq 0 -and $parsed.media_kind -eq 'disk' -and $parsed.boot_architecture -eq 'x86_64') 'APM parser identifies x86_64 PE booters'
    $badPe = [IO.File]::ReadAllBytes((Join-Path $fixtureDirectory 'boot.efi'))
    $badPe[132] = 0x64; $badPe[133] = 0xaa
    [IO.File]::WriteAllBytes((Join-Path $fixtureDirectory 'boot.efi'), $badPe)
    $mediaParser | & $python - (Join-Path $fixtureDirectory 'media.iso') $fixtureDirectory 2>$null | Out-Null
    Assert-Condition ($LASTEXITCODE -ne 0) 'ARM64 booters are refused'
    [IO.File]::WriteAllBytes((Join-Path $fixtureDirectory 'media.iso'), [byte[]]::new(32775))
    $mediaParser | & $python - (Join-Path $fixtureDirectory 'media.iso') $fixtureDirectory 2>$null | Out-Null
    Assert-Condition ($LASTEXITCODE -ne 0) 'Unknown containers are refused even with an .iso suffix'

    # Check Windows command-line quoting by asking a native process what it received.
    $echo = Join-Path $testRoot 'argv.py'
    $echoOutput = Join-Path $testRoot 'argv.json'
    'import json,pathlib,sys; pathlib.Path(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))' | Set-Content -LiteralPath $echo
    $values = @('space in path', 'quote"value', 'trailing\', 'comma,path', '')
    $echoArgs = @($echo, $echoOutput) + $values
    $echoProcess = Start-Process -FilePath $python -ArgumentList (($echoArgs | ForEach-Object { ConvertTo-ReimsWindowsArgument $_ }) -join ' ') -WindowStyle Hidden -PassThru -Wait
    Assert-Condition ($echoProcess.ExitCode -eq 0) 'Native quoting fixture runs'
    $received = Get-Content -Raw -LiteralPath $echoOutput | ConvertFrom-Json
    Assert-Condition (($received | ConvertTo-Json -Compress) -eq ($values | ConvertTo-Json -Compress)) 'Windows quoting preserves every argument'

    & (Join-Path $testScripts 'snapshot.ps1') -Action Create -Name baseline -QemuImg $QemuImg | Out-Null
    $changed = Get-ReimsVmConfig
    Assert-Condition ($changed.active_disk -ne $active) 'Snapshot starts a new overlay'
    Invoke-ReimsTool $QemuIo @('-f', 'qcow2', '-c', 'write -P 0x2a 0 512', $changed.active_disk) | Out-Null
    'modified vars' | Set-Content -LiteralPath $vars
    Assert-Throws { & (Join-Path $testScripts 'snapshot.ps1') -Action Create -Name baseline -QemuImg $QemuImg } 'already exists'
    & (Join-Path $testScripts 'snapshot.ps1') -Action Restore -Name baseline -QemuImg $QemuImg | Out-Null
    $restored = Get-ReimsVmConfig
    Invoke-ReimsTool $QemuIo @('-f', 'qcow2', '-c', 'read -P 0x7a 0 512', $restored.active_disk) | Out-Null
    Assert-Condition ((Get-Content -Raw -LiteralPath $restored.firmware_vars).Trim() -eq 'firmware') 'Restore includes NVRAM'
    Assert-Condition ((Get-FileHash -LiteralPath $base).Hash -eq $baseHash) 'Snapshots never alter the base disk'
    'different code' | Set-Content -LiteralPath $code
    Assert-Throws { & (Join-Path $testScripts 'snapshot.ps1') -Action Restore -Name baseline -QemuImg $QemuImg } 'Firmware/OpenCore changed'

    $ready = Join-Path $testRoot 'qmp-ready.json'
    $mockArgs = @((Join-Path $PSScriptRoot 'mock-qmp.py'), '--ready', $ready)
    $mock = Start-Process -FilePath $python -ArgumentList (($mockArgs | ForEach-Object { ConvertTo-ReimsWindowsArgument $_ }) -join ' ') -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (!(Test-Path -LiteralPath $ready)) {
        if ($mock.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'QMP fixture did not start.' }
        Start-Sleep -Milliseconds 50
    }
    $runtime = [pscustomobject]@{
        pid = $mock.Id; start_ticks = $mock.StartTime.ToUniversalTime().Ticks; executable = $mock.Path
        qmp_port = (Get-Content -Raw -LiteralPath $ready | ConvertFrom-Json).port
        run_directory = Join-Path $testRoot 'vm/logs/mock'; disk = $restored.active_disk; diagnostic_only = $false
    }
    New-Item -ItemType Directory -Force -Path $runtime.run_directory | Out-Null
    'reims-vgpu: fatal: fixture only' | Set-Content -LiteralPath (Join-Path $runtime.run_directory 'stderr.log')
    Write-ReimsJson (Join-Path $testRoot 'vm/state/runtime.json') $runtime
    Assert-Condition (Invoke-ReimsQmp $runtime 'query-status').running 'QMP skips events and unrelated response IDs'
    Assert-Throws { Invoke-ReimsQmp $runtime 'fixture-error' } 'fixture failure'
    Assert-Throws { Assert-ReimsVmStopped } 'Stop this VM'
    $wrong = $runtime.PSObject.Copy()
    $wrong.start_ticks++
    Assert-Throws { Get-ReimsVmProcess $wrong } 'belongs to another process'
    & (Join-Path $testScripts 'collect-logs.ps1') -Screenshot | Out-Null
    $report = Get-ChildItem -LiteralPath (Join-Path $testRoot '.work/diagnostics') -Directory -Filter 'vm-*' | Select-Object -Last 1
    Assert-Condition (Test-Path -LiteralPath (Join-Path $report.FullName 'guest.ppm')) 'Collect uses guest QMP screendump'
    Assert-Condition ((Get-Content -Raw -LiteralPath (Join-Path $report.FullName 'failures.txt')) -match 'fixture only') 'Fatal log lines are retained'
    & (Join-Path $testScripts 'benchmark.ps1') -Seconds 1 | Out-Null
    $benchmark = Get-ChildItem -LiteralPath (Join-Path $testRoot '.work/diagnostics') -Directory -Filter 'benchmark-*' | Select-Object -Last 1
    $summary = Get-Content -Raw -LiteralPath (Join-Path $benchmark.FullName 'summary.json') | ConvertFrom-Json
    Assert-Condition ($summary.sample_count -ge 1 -and $summary.display_stats -eq 'no samples reported during this interval') 'Benchmark reports measured host samples and absent frame evidence'
    & (Join-Path $testScripts 'stop.ps1') -TimeoutSeconds 2 | Out-Null
    $mock.WaitForExit(5000) | Out-Null
    Assert-Condition $mock.HasExited 'Stop uses QMP powerdown on the recorded process'

    if ($PreparedArtifactsRoot) {
        $media = Get-Content -Raw -LiteralPath (Join-Path $PreparedArtifactsRoot 'vm/state/media.json') | ConvertFrom-Json
        $prepared = Get-Content -Raw -LiteralPath (Join-Path $PreparedArtifactsRoot 'vm/state/config.json') | ConvertFrom-Json
        $opencore = Get-Content -Raw -LiteralPath (Join-Path $PreparedArtifactsRoot 'vm/state/opencore.json') | ConvertFrom-Json
        Assert-Condition ($media.boot_architecture -eq 'x86_64' -and $media.media_kind -eq 'disk') 'Prepared APM installer contains an x86_64 booter'
        Assert-Condition ((Get-FileHash -LiteralPath $opencore.image).Hash -eq $opencore.image_sha256) 'Prepared EFI image hash agrees with manifest'
        Invoke-ReimsTool $opencore.ocvalidate @($opencore.config) | Out-Null
        $sevenZip = Get-ReimsTool '7z.exe'
        $efiListing = (Invoke-ReimsTool $sevenZip @('l', '-slt', $opencore.image)) -join "`n"
        Assert-Condition ($efiListing -match 'EFI[\\/]BOOT[\\/]BOOTx64\.efi' -and $efiListing -match 'EFI[\\/]OC[\\/]config\.plist') 'Generated FAT image holds the EFI fallback loader and plist'
        $imageConfig = Join-Path $testRoot 'image-config.plist'
        $imageCheck = @'
import pathlib, plistlib, subprocess, sys
image, source, sevenzip, target = sys.argv[1:]
raw = subprocess.run([sevenzip, 'e', '-so', image, r'EFI\OC\config.plist'], check=True, capture_output=True).stdout
assert raw == pathlib.Path(source).read_bytes(), 'EFI image config differs from the validated source'
c = plistlib.loads(raw)
apple = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
assert c['NVRAM']['Add'][apple]['csr-active-config'] == bytes(4)
assert 'amfi' not in c['NVRAM']['Add'][apple]['boot-args'].lower()
assert c['Misc']['Security']['DmgLoading'] == 'Signed'
pathlib.Path(target).write_bytes(raw)
'@
        $imageCheck | & $python - $opencore.image $opencore.config $sevenZip $imageConfig
        Assert-Condition ($LASTEXITCODE -eq 0) 'EFI image matches its validated config and preserves SIP/AMFI settings'
        Invoke-ReimsTool $opencore.ocvalidate @($imageConfig) | Out-Null
        $preparedInfo = (Invoke-ReimsTool $QemuImg @('info', '--output=json', $prepared.base_disk)) -join "`n" | ConvertFrom-Json
        Assert-Condition ($preparedInfo.'virtual-size' -eq 128GB -and $preparedInfo.'actual-size' -lt 1MB) '128 GiB base is sparse'
    }
    $result = [ordered]@{ assertions = $script:assertions; passed = $true; vm_boot = $false; evidence = 'native tools and loopback QMP fixture' }
    $ProjectRoot = $artifactRoot
    Write-ReimsJson (Join-Path $artifactRoot '.work/diagnostics/firmware-vm/self-checks.json') $result
    $result | ConvertTo-Json
} finally {
    if ($mock -and !$mock.HasExited) { Stop-Process -InputObject $mock -Force }
    $env:REIMS_PROJECT_ROOT_OVERRIDE = $oldOverride
    $ProjectRoot = $artifactRoot
    $verified = Assert-ReimsArtifactPath $testRoot
    Remove-Item -LiteralPath $verified -Recurse -Force
    . $EnvironmentScript
}
