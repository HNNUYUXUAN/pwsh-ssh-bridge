#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Upload','Download')][string]$Direction,
    [Parameter(Mandatory)][string]$ConfigFile,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][string]$LocalPath,
    [Parameter(Mandatory)][string]$RemotePath,
    [Parameter(Mandatory)][switch]$AllowDestinationOverwrite,
    [ValidateRange(1,86400)][int]$TimeoutSeconds=120
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
try {
    if (-not $AllowDestinationOverwrite) { throw 'This copy can replace its destination. Use a unique staging filename, then pass AllowDestinationOverwrite only for an authorized destination.' }
    Assert-BridgeAlias $Alias
    $config = Get-BridgeFile $ConfigFile
    if (-not $RemotePath.StartsWith('/') -or $RemotePath.EndsWith('/') -or $RemotePath -match '[\x00-\x1f*?\[\]{}\\]') { throw 'RemotePath must be an absolute POSIX file path without control characters, backslashes or wildcard characters.' }
    $local = [IO.Path]::GetFullPath($LocalPath)
    if ($Direction -eq 'Upload') { $local = Get-BridgeFile $local }
    elseif (-not (Test-Path -LiteralPath (Split-Path -Parent $local) -PathType Container)) { throw 'Create the local destination parent directory first.' }
    if (Test-Path -LiteralPath $local -PathType Container) { throw 'LocalPath must name a file, not a directory.' }
    $ssh = Resolve-BridgeTool ssh
    $version = Invoke-BridgeProcess $ssh @('-V') -TimeoutSeconds 10
    if (($version.Err.Text + $version.Out.Text) -notmatch 'OpenSSH(?:_for_Windows)?_(\d+)\.') { throw 'Cannot determine the OpenSSH version.' }
    if ([int]$Matches[1] -lt 9) { throw 'Copy helper requires OpenSSH 9 or newer for SFTP-by-default. Use an explicitly reviewed SFTP workflow on older clients.' }
    # scp and ssh must come from the same OpenSSH installation.
    $scp = Join-Path (Split-Path -Parent $ssh) $(if ($IsWindows) {'scp.exe'} else {'scp'})
    if (-not (Test-Path -LiteralPath $scp -PathType Leaf)) { throw 'Matching scp executable is missing.' }
    $quote = "'" + $RemotePath.Replace("'", "'" + '"' + "'" + '"' + "'") + "'"
    $check = "set -eu`np=$quote`nif [ -d " + '"$p"' + ' ] || [ -L "$p" ]; then echo "Remote path is a directory or symlink" >&2; exit 61; fi' + "`n"
    if ($Direction -eq 'Download') { $check += 'test -f "$p"' + "`n" }
    $preflight = Invoke-BridgeProcess $ssh (@(Get-BridgeSshArguments $config $Alias) + @('sh','-s')) -InputText $check -TimeoutSeconds 30
    if ($preflight.TimedOut -or $preflight.ExitCode -ne 0) {
        ConvertTo-BridgeResult $preflight 'copy_preflight' $Alias | ConvertTo-Json -Compress -Depth 5
        exit 2
    }
    $remote = "${Alias}:$RemotePath"
    $argv = @('-B','-F',$config,'-o','StrictHostKeyChecking=yes','-o','BatchMode=yes',
        '-o','ForwardAgent=no','-o','ClearAllForwardings=yes','-o','ConnectTimeout=10',
        '-o','ServerAliveInterval=30','-o','ServerAliveCountMax=3')
    $argv += if ($Direction -eq 'Upload') { @($local,$remote) } else { @($remote,$local) }
    $result = Invoke-BridgeProcess $scp $argv -TimeoutSeconds $TimeoutSeconds
    $report = ConvertTo-BridgeResult $result $Direction.ToLowerInvariant() $Alias
    $report['destinationMayBePartial'] = ($result.TimedOut -or $result.ExitCode -ne 0)
    $report | ConvertTo-Json -Compress -Depth 5
    if ($result.TimedOut) { exit 124 }
    exit $result.ExitCode
} catch {
    Write-BridgeFailure 'copy' $_.Exception.Message
    exit 2
}
