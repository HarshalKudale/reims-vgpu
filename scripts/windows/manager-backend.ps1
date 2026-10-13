#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('Status','Setup','BuildEngine','EnableWhpx','Start','PowerOff','Restart','Exit','ForceExit','Pause','Resume','SnapshotCreate','SnapshotRestore','GenerateIdentity','EnableAppleAccount','DisableAppleAccount','SetResolution','ApplyResolution','SetNetwork','SetHardware','ExpandDisk','CreateBridge','InstallTap','Pair','CollectLogs')][string]$Action = 'Status',
    [string]$Iso,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$')][string]$Name,
    [ValidateSet('1280x720','1920x1080','2560x1440','3840x2160')][string]$Resolution = '1920x1080',
    [ValidateSet('nat','bridge')][string]$Network = 'nat',
    [string]$Adapter, [string]$PhysicalAdapter, [string]$Installer,
    [ValidatePattern('^[a-z_][a-z0-9_-]*$')][string]$User,
    [string]$GuestHost, [string]$Fingerprint,
    [ValidateRange(1,64)][int]$Cpus = 8,
    [ValidateRange(4096,131072)][int]$MemoryMiB = 8192,
    [ValidateRange(64,2048)][int]$DiskGiB = 128,
    [ValidateSet('none','dsound')][string]$Audio = 'none',
    [switch]$WithInstaller
)
$env:REIMS_PROJECT_ROOT_OVERRIDE = [IO.Path]::GetFullPath($Root)
. "$PSScriptRoot/start.ps1" -FunctionsOnly

function Get-GuestEndpoint($Config) {
    if ((Get-ReimsNetworkMode $Config) -eq 'nat') { return @{host='127.0.0.1';port=$Config.ssh_port} }
    if ($Config.network.guest_host -notmatch '^[A-Za-z0-9][A-Za-z0-9.:-]*$') { throw 'ブリッジの macOS IP アドレスを設定してください。' }
    return @{host=$Config.network.guest_host;port=22}
}

function Invoke-GuestControl([string]$Operation, [string]$Command) {
    $runtime = Get-ReimsRuntime
    if (!$runtime -or !(Get-ReimsVmProcess $runtime)) { throw 'VM は停止しています。' }
    $state = (Invoke-ReimsQmp $runtime 'query-status').status
    if ($state -eq 'shutdown' -and $Operation -eq '-h') { 'macOS は電源オフ済みです。'; return }
    if ($state -ne 'running') { throw "VM は $state です。電源操作の前に再開してください。" }
    $guestPath = Join-Path $ProjectRoot 'vm/state/guest.json'
    $setupPath = Join-Path $ProjectRoot 'vm/state/setup.json'
    $account = if (Test-Path $guestPath) { (Get-Content $guestPath -Raw | ConvertFrom-Json).user }
        elseif (Test-Path $setupPath) { (Get-Content $setupPath -Raw | ConvertFrom-Json).account_name }
        else { throw 'macOS で ReimsTools の setup.command を実行し、接続タブでペアリングしてください。' }
    if ($account -notmatch '^[a-z_][a-z0-9_-]*$') { throw 'Invalid guest account name.' }
    $key = Join-Path $ProjectRoot 'vm/state/ssh/id_ed25519'
    $known = Join-Path $ProjectRoot 'vm/state/known_hosts'
    if (!(Test-Path $key) -or !(Test-Path $known)) { throw 'SSH キーとホスト鍵が未設定です。' }
    $endpoint = Get-GuestEndpoint (Get-ReimsVmConfig)
    $guest = if (Test-Path $guestPath) { Get-Content $guestPath -Raw | ConvertFrom-Json } else { $null }
    $alias = if ($guest -and $guest.PSObject.Properties['host_key_alias']) { @('-o', "HostKeyAlias=$($guest.host_key_alias)") } else { @() }
    $output = @(& "$env:SystemRoot/System32/OpenSSH/ssh.exe" -F NUL -n -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes `
        -o "UserKnownHostsFile=$known" -o KexAlgorithms=curve25519-sha256 @alias -p $endpoint.port -i $key `
        "$account@$($endpoint.host)" $(if ($Command) {$Command} else {"sudo -n /sbin/shutdown $Operation now"}) 2>&1 | ForEach-Object ToString)
    $exitCode = $LASTEXITCODE
    if ($Command) {
        if ($exitCode -ne 0) { throw "macOS の操作に失敗しました ($exitCode): $($output -join ' ')" }
        return $output -join "`n"
    }
    if ($Operation -eq '-h') {
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (!(Get-ReimsVmProcess $runtime) -or (Invoke-ReimsQmp $runtime 'query-status').status -eq 'shutdown') { 'macOS の電源オフを確認しました。'; return }
            Start-Sleep -Milliseconds 250
        }
    } elseif ($exitCode -eq 0 -or ($output -join "`n") -match '(?m)^Shutdown NOW!') {
        'macOS が再起動コマンドを受け付けました。'; return
    }
    throw "SSH 電源操作を確認できませんでした ($exitCode): $($output -join ' ')"
}

function Assert-Administrator {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'この操作には Windows の管理者権限が必要です。' }
}

if ($Action -eq 'Status') {
    $runtime = Get-ReimsRuntime
    $prepared = Test-Path (Join-Path $ProjectRoot 'vm/state/config.json')
    $state = if ($prepared) { 'stopped' } else { 'unprepared' }
    if ($runtime -and (Get-ReimsVmProcess $runtime)) { $state = (Invoke-ReimsQmp $runtime 'query-status').status }
    $snapshots = @(& "$PSScriptRoot/snapshot.ps1" -Action List | ForEach-Object name)
    $config = if ($prepared) { Get-ReimsVmConfig } else { $null }
    $adapters = @(Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,HardwareInterface)
    $taps = @(Get-ReimsTapAdapters | ForEach-Object Name)
    $withInstaller = $false
    if ($config -and $config.PSObject.Properties['connect_installer']) { $withInstaller = $config.connect_installer }
    if ($runtime -and (Get-ReimsVmProcess $runtime)) {
        $launch = Get-Content -Raw (Join-Path $runtime.run_directory 'command.json') | ConvertFrom-Json
        $withInstaller = [bool]($launch.arguments | Where-Object { $_ -like 'id=installer,*' })
    }
    @{state=$state; prepared=$prepared; snapshots=$snapshots; taps=$taps; adapters=$adapters;
        cpus=$(if ($config) {$config.cpus} else {8}); memory_mib=$(if ($config) {$config.memory_mib} else {8192});
        disk_gib=$(if ($config) {$config.disk_gib} else {128}); disk=$(if ($config) {$config.active_disk} else {''});
        audio=$(if ($config -and $config.PSObject.Properties['audio']) {$config.audio} else {'none'});
        with_installer=$withInstaller; network_adapter=$(if ($config -and $config.PSObject.Properties['network']) {$config.network.adapter} else {''});
        guest_host=$(if ($config -and $config.PSObject.Properties['network']) {$config.network.guest_host} else {''});
        resolution=$(if ($config) {$config.resolution} else {'1920x1080'});
        network=$(if ($config) {Get-ReimsNetworkMode $config} else {'nat'});
        iso=$(if ($config) {$config.iso} else {''})} | ConvertTo-Json -Depth 5 -Compress
    return
}
switch ($Action) {
    BuildEngine {
        Assert-ReimsVmStopped
        if (!(Test-Path (Join-Path $ProjectRoot 'Cargo.toml')) -or (Test-Path (Join-Path $ProjectRoot '.git') -PathType Leaf)) { throw '本体リポジトリの通常のチェックアウトを選択してください。' }
        & "$PSScriptRoot/bootstrap.ps1"
        & "$PSScriptRoot/build.ps1"
    }
    EnableWhpx {
        Assert-ReimsVmStopped
        Assert-Administrator
        & "$PSScriptRoot/enable-whpx.ps1"
    }
    Setup {
        Assert-ReimsVmStopped
        if (!$Iso) { throw 'macOS インストーラーを選択してください。' }
        & "$PSScriptRoot/prepare-opencore.ps1" -Rebuild | Out-Null
        & "$PSScriptRoot/prepare-vm.ps1" -Iso $Iso -DiskGiB $DiskGiB | Out-Null
        if (!(Test-Path (Join-Path $ProjectRoot 'vm/state/opencore-identity.json'))) {
            & "$PSScriptRoot/prepare-opencore.ps1" -GenerateIdentity -Rebuild | Out-Null
        }
        & "$PSScriptRoot/prepare-tools.ps1"
        '準備完了。インストーラー付きで起動し、macOS インストール後に ReimsTools の setup.command を実行してください。'
    }
    Start { & "$PSScriptRoot/start.ps1" -WithoutInstaller:(!$WithInstaller) }
    PowerOff { Invoke-GuestControl '-h'; & "$PSScriptRoot/stop.ps1" }
    Restart { Invoke-GuestControl '-r' }
    Exit {
        $runtime = Get-ReimsRuntime
        if ($runtime -and (Get-ReimsVmProcess $runtime) -and (Invoke-ReimsQmp $runtime 'query-status').status -ne 'shutdown') { Invoke-GuestControl '-h' }
        & "$PSScriptRoot/stop.ps1" -Exit
    }
    ForceExit { & "$PSScriptRoot/stop.ps1" -Force }
    Pause { & "$PSScriptRoot/qmp.ps1" -Command stop }
    Resume { & "$PSScriptRoot/qmp.ps1" -Command cont }
    SnapshotCreate { & "$PSScriptRoot/snapshot.ps1" -Action Create -Name $Name }
    SnapshotRestore { & "$PSScriptRoot/snapshot.ps1" -Action Restore -Name $Name }
    GenerateIdentity { & "$PSScriptRoot/prepare-opencore.ps1" -GenerateIdentity -Rebuild }
    EnableAppleAccount { & "$PSScriptRoot/prepare-opencore.ps1" -AppleAccountCompatibility Enable -Rebuild }
    DisableAppleAccount { & "$PSScriptRoot/prepare-opencore.ps1" -AppleAccountCompatibility Disable -Rebuild }
    SetResolution {
        Assert-ReimsVmStopped
        $config = Get-ReimsVmConfig
        $config.resolution = $Resolution
        Write-ReimsJson (Join-Path $ProjectRoot 'vm/state/config.json') $config
        '解像度を保存しました。次回起動時に適用します。'
    }
    ApplyResolution {
        $js = Get-Content -Raw -LiteralPath "$PSScriptRoot/guest-display.js"
        Invoke-GuestControl -Command "/usr/bin/osascript -l JavaScript - $Resolution <<'REIMS_DISPLAY'`n$js`nREIMS_DISPLAY"
    }
    SetNetwork {
        Assert-ReimsVmStopped
        if ($Network -eq 'bridge' -and $Adapter -notin @(Get-ReimsTapAdapters | ForEach-Object Name)) { throw '実在する TAP-Windows アダプターを選択してください。' }
        if ($GuestHost -and $GuestHost -notmatch '^[A-Za-z0-9][A-Za-z0-9.:-]*$') { throw 'Invalid macOS IP / hostname.' }
        $config = Get-ReimsVmConfig
        $config | Add-Member -Force network @{mode=$Network; adapter=$Adapter; guest_host=$GuestHost}
        Write-ReimsJson (Join-Path $ProjectRoot 'vm/state/config.json') $config
        'ネットワーク設定を保存しました。次回起動時に適用します。'
    }
    SetHardware {
        Assert-ReimsVmStopped
        if ($MemoryMiB % 4 -ne 0) { throw 'メモリは 4 MiB 単位で指定してください。' }
        $hostInfo = Get-CimInstance Win32_ComputerSystem
        if ($Cpus -gt $hostInfo.NumberOfLogicalProcessors -or [long]$MemoryMiB * 1MB -ge $hostInfo.TotalPhysicalMemory) { throw 'ホストの CPU / メモリ容量以内で設定してください。' }
        if ($Network -eq 'bridge' -and $Adapter -notin @(Get-ReimsTapAdapters | ForEach-Object Name)) { throw 'TAP adapter not found.' }
        if ($GuestHost -and $GuestHost -notmatch '^[A-Za-z0-9][A-Za-z0-9.:-]*$') { throw 'Invalid guest address.' }
        if ($Iso) { & "$PSScriptRoot/prepare-vm.ps1" -Iso $Iso | Out-Null }
        $config = Get-ReimsVmConfig
        $config.cpus = $Cpus; $config.memory_mib = $MemoryMiB; $config.resolution = $Resolution
        $config | Add-Member -Force audio $Audio
        $config | Add-Member -Force connect_installer ([bool]$WithInstaller)
        $config | Add-Member -Force network @{mode=$Network;adapter=$Adapter;guest_host=$GuestHost}
        Write-ReimsJson (Join-Path $ProjectRoot 'vm/state/config.json') $config
        '仮想マシン設定を保存しました。次回起動に適用します。'
    }
    ExpandDisk {
        Assert-ReimsVmStopped
        $config = Get-ReimsVmConfig
        $tool = Get-ReimsTool 'qemu-img.exe'
        $info = (Invoke-ReimsTool $tool @('info','--output=json',$config.active_disk)) -join "`n" | ConvertFrom-Json
        if ([long]$DiskGiB * 1GB -le $info.'virtual-size') { throw '現在より大きな容量を指定してください。縮小は行いません。' }
        $next = Join-Path $ProjectRoot ('vm/disks/' + [guid]::NewGuid() + '.qcow2')
        Invoke-ReimsTool $tool @('check','-q',$config.active_disk) | Out-Null
        Invoke-ReimsTool $tool @('create','-f','qcow2','-F','qcow2','-b',$config.active_disk,$next) | Out-Null
        Invoke-ReimsTool $tool @('resize',$next,"$($DiskGiB)G") | Out-Null
        $config.active_disk = $next; $config.disk_gib = $DiskGiB
        Write-ReimsJson (Join-Path $ProjectRoot 'vm/state/config.json') $config
        '仮想ディスクを拡張しました。macOS の Disk Utility でも APFS 領域を拡張してください。以前のディスクは保持しています。'
    }
    CreateBridge {
        Assert-ReimsVmStopped
        Assert-Administrator
        if ($Adapter -notin @(Get-ReimsTapAdapters | ForEach-Object Name)) { throw 'TAP adapter not found.' }
        $physical = @(Get-NetAdapter | Where-Object { $_.Name -eq $PhysicalAdapter -and $_.HardwareInterface })
        if ($physical.Count -ne 1) { throw '実在する物理ネットワークアダプターを選択してください。' }
        Invoke-ReimsTool "$env:SystemRoot/System32/netsh.exe" @('bridge','create',$Adapter,$PhysicalAdapter)
    }
    InstallTap {
        Assert-Administrator
        $file = Get-Item -LiteralPath $Installer
        if ($file.Extension -ne '.exe') { throw '公式 TAP-Windows インストーラー (.exe) を選択してください。' }
        $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'OpenVPN') { throw '有効な OpenVPN 署名のないインストーラーは実行しません。' }
        $process = Start-Process -FilePath $file.FullName -ArgumentList '/S' -WindowStyle Hidden -PassThru -Wait
        if ($process.ExitCode -ne 0) { throw "TAP installer failed ($($process.ExitCode))." }
    }
    Pair {
        if (!$User -or $Fingerprint -notmatch '^SHA256:[A-Za-z0-9+/]{43}$') { throw 'macOS のユーザー名と setup.command が表示した SHA256 指紋を入力してください。' }
        $endpoint = Get-GuestEndpoint (Get-ReimsVmConfig)
        $scanner = Join-Path $MsysRoot 'usr/bin/ssh-keyscan.exe'
        $scan = @(& $scanner -T 5 -t ed25519 -p $endpoint.port $endpoint.host 2>$null | Where-Object { $_ -match '^[^#].* ssh-ed25519 ' })
        if ($LASTEXITCODE -ne 0 -or $scan.Count -ne 1) { throw 'macOS SSH ホスト鍵を取得できませんでした。' }
        $blob = [Convert]::FromBase64String(($scan[0] -split '\s+')[2])
        $actual = 'SHA256:' + [Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData($blob)).TrimEnd('=')
        if ($actual -cne $Fingerprint) { throw 'ホスト鍵の指紋が一致しません。保存しませんでした。' }
        $known = Join-Path $ProjectRoot 'vm/state/known_hosts'
        $alias = 'reims-macos'
        $line = $alias + ' ssh-ed25519 ' + [Convert]::ToBase64String($blob)
        $lines = if (Test-Path $known) { @(Get-Content $known | Where-Object { $_ -notlike "$alias *" }) } else { @() }
        @($lines) + $line | Set-Content -LiteralPath $known -Encoding utf8NoBOM
        Write-ReimsJson (Join-Path $ProjectRoot 'vm/state/guest.json') @{user=$User;host_key_alias=$alias}
        'SSH ホスト鍵を照合し、接続設定を保存しました。'
    }
    CollectLogs { & "$PSScriptRoot/collect-logs.ps1" -Screenshot }
}
