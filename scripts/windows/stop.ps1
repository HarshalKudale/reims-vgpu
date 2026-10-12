#Requires -Version 7.2
[CmdletBinding()]
param([ValidateRange(1, 300)][int]$TimeoutSeconds = 60, [switch]$Force)
. "$PSScriptRoot/start.ps1" -FunctionsOnly
$runtime = Get-ReimsRuntime
if (!$runtime -or !(Get-ReimsVmProcess $runtime)) { 'The recorded VM is stopped.'; return }
try { Invoke-ReimsQmp $runtime $(if ($runtime.diagnostic_only) { 'quit' } else { 'system_powerdown' }) | Out-Null } catch {
    if (!$Force) { throw }
    Write-Warning $_.Exception.Message
}
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    if (!(Get-ReimsVmProcess $runtime)) { 'QEMU stopped.'; return }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $deadline)
if (!$Force) { throw 'Guest has not shut down. Use stop.ps1 -Force only to discard its unsaved work.' }
try { Invoke-ReimsQmp $runtime 'quit' | Out-Null } catch { Write-Warning $_.Exception.Message }
Start-Sleep -Milliseconds 500
$owned = Get-ReimsVmProcess $runtime
if ($owned) { Stop-Process -InputObject $owned -Force }
'Powered off the recorded VM.'
