#Requires -Version 7.2
[CmdletBinding()]
param([string]$ConfigFile, [string]$Alias)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
$checks = [ordered]@{}
foreach ($name in @('ssh','ssh-keygen','ssh-keyscan','scp')) {
    try { $checks[$name] = @{ available=$true; path=(Resolve-BridgeTool $name) } }
    catch { $checks[$name] = @{ available=$false; error=$_.Exception.Message } }
}
$identity = if ($IsWindows) { [Security.Principal.WindowsIdentity]::GetCurrent().Name } else { [Environment]::UserName }
$report = [ordered]@{
    schemaVersion=1; operation='environment'; powershellVersion=$PSVersionTable.PSVersion.ToString()
    os=[Runtime.InteropServices.RuntimeInformation]::OSDescription
    identity=$identity; workingDirectory=(Get-Location).Path
    tools=$checks; configChecked=$false; networkTested=$false
    next='Resolve missing dependencies, then configure host trust and run Invoke-Bridge.ps1 -Probe.'
}
if ($checks.ssh.available) {
    $version = Invoke-BridgeProcess $checks.ssh.path @('-V') -TimeoutSeconds 10
    $report['sshVersion'] = ($version.Err.Text + $version.Out.Text).Trim()
}
if ($ConfigFile) {
    try {
        if (-not $Alias) { throw 'Provide Alias with ConfigFile.' }
        Assert-BridgeAlias $Alias
        $config = Get-BridgeFile $ConfigFile
        # ssh -G can evaluate Match exec; use only a user-approved configuration.
        $resolved = Invoke-BridgeProcess (Resolve-BridgeTool ssh) @('-F',$config,'-G',$Alias) -TimeoutSeconds 10
        $report.configChecked = $true
        $report['configExitCode'] = $resolved.ExitCode
        $report['configSummary'] = @($resolved.Out.Text -split "`n" | Where-Object { $_ -match '^(hostname|user|port|identityfile|hostkeyalias|userknownhostsfile|stricthostkeychecking|batchmode) ' })
        $report['configError'] = $resolved.Err.Text
    } catch { $report['configError'] = $_.Exception.Message }
}
$report | ConvertTo-Json -Depth 6
if (-not $checks.ssh.available -or -not $checks.'ssh-keygen'.available) { exit 2 }
if ($ConfigFile -and (-not $report.configChecked -or $report.configExitCode -ne 0)) { exit 2 }
