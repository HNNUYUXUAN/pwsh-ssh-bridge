#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][string]$HostName,
    [ValidateRange(1,65535)][int]$Port=22,
    [Parameter(Mandatory)][string]$UserName,
    [Parameter(Mandatory)][string]$IdentityFile,
    [Parameter(Mandatory)][string]$HostPublicKeyFile,
    [Parameter(Mandatory)][string]$ExpectedFingerprint
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
try {
    Assert-BridgeAlias $Alias
    if ($HostName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:%_-]*$' -or $HostName.Contains('%')) { throw 'HostName must be a literal DNS name or IP address.' }
    if ($UserName -notmatch '^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$') { throw 'Invalid Linux account name.' }
    if ($ExpectedFingerprint -cnotmatch '^SHA256:[A-Za-z0-9+/]{43}$') { throw 'ExpectedFingerprint must be the SHA256 fingerprint obtained through the trusted remote console.' }
    $identity = Get-BridgeFile $IdentityFile
    $hostKeyFile = Get-BridgeFile $HostPublicKeyFile
    $keyLine = [IO.File]::ReadAllText($hostKeyFile).Trim()
    if ($keyLine -notmatch '^ssh-ed25519 ([A-Za-z0-9+/]+={0,2})(?: [^\r\n]*)?$') { throw 'Provide exactly one ssh-ed25519 host public-key line, copied from the remote console.' }
    $hostBlob = $Matches[1]
    $fingerprint = Invoke-BridgeProcess (Resolve-BridgeTool ssh-keygen) @('-lf',$hostKeyFile,'-E','sha256') -TimeoutSeconds 10
    if ($fingerprint.ExitCode -ne 0 -or ($fingerprint.Out.Text.Trim() -split '\s+')[1] -cne $ExpectedFingerprint) { throw 'Host public key does not match the independently obtained fingerprint.' }
    $destination = [IO.Path]::GetFullPath($Directory)
    if (Test-Path -LiteralPath $destination) { throw 'Profile directory already exists. Choose a new directory; review endpoint changes explicitly.' }
    $configFile = Join-Path $destination 'ssh_config'
    $knownHosts = Join-Path $destination 'known_hosts'
    $identityQuoted = ConvertTo-BridgeConfigPath $identity
    $knownQuoted = ConvertTo-BridgeConfigPath $knownHosts
    $hostAlias = "bridge-$Alias"
    $configText = @"
Host $Alias
    HostName $HostName
    Port $Port
    User $UserName
    HostKeyAlias $hostAlias
    IdentityFile $identityQuoted
    IdentitiesOnly yes
    UserKnownHostsFile $knownQuoted
    GlobalKnownHostsFile none
    StrictHostKeyChecking yes
    HostKeyAlgorithms ssh-ed25519
    UpdateHostKeys no
    BatchMode yes
    ForwardAgent no
    ForwardX11 no
    PermitLocalCommand no
    ConnectTimeout 10
    ConnectionAttempts 1
    ServerAliveInterval 30
    ServerAliveCountMax 3
"@
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    [IO.File]::WriteAllText($knownHosts, "$hostAlias ssh-ed25519 $hostBlob`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($configFile, $configText.Replace("`r`n","`n") + "`n", [Text.UTF8Encoding]::new($false))
    [ordered]@{schemaVersion=1; operation='profile'; outcome='created'; configFile=$configFile; alias=$Alias; fingerprint=$ExpectedFingerprint; networkTested=$false} | ConvertTo-Json -Compress
} catch {
    Write-BridgeFailure 'profile' $_.Exception.Message
    exit 2
}
