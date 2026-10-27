#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigFile,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][ValidateRange(1024,65535)][int]$LocalPort,
    [Parameter(Mandatory)][string]$RemoteHost,
    [Parameter(Mandatory)][ValidateRange(1,65535)][int]$RemotePort
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
try {
    Assert-BridgeAlias $Alias
    $config = Get-BridgeFile $ConfigFile
    if ($RemoteHost -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') { throw 'RemoteHost must be an IPv4 address or DNS name.' }
    # Check occupancy explicitly: Windows/OpenSSH socket sharing can otherwise
    # leave a second forwarding process alive for an already occupied port.
    $reservation = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$LocalPort)
    try {
        $reservation.Server.ExclusiveAddressUse = $true
        $reservation.Start()
    } catch { throw 'The local loopback port is unavailable. Choose another port; do not terminate an unrelated process.' }
    finally { $reservation.Stop() }
    # A race remains after this check; SSH's bind check and service verification
    # are still required. This script does not claim atomic port reservation.
    $forward = "127.0.0.1:${LocalPort}:${RemoteHost}:${RemotePort}"
    Write-Host "Starting foreground SSH forwarding on 127.0.0.1:$LocalPort. Keep this process alive; stop with Ctrl+C. Verify the forwarded service separately."
    $argv = @('-F',$config,'-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',
        '-o','ForwardAgent=no','-o','ForwardX11=no','-o','PermitLocalCommand=no',
        '-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=10',
        '-o','ServerAliveInterval=30','-o','ServerAliveCountMax=3','-N','-T','-L',$forward,$Alias)
    & (Resolve-BridgeTool ssh) @argv
    exit $LASTEXITCODE
} catch { Write-Error $_.Exception.Message; exit 2 }
