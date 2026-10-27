#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$Unattended
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
try {
    $key = [IO.Path]::GetFullPath($Path)
    if ((Test-Path -LiteralPath $key) -or (Test-Path -LiteralPath "$key.pub")) { throw 'A key or public key already exists at this path. Reuse it or select a new path.' }
    $parent = Split-Path -Parent $key
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Create a private credential directory first, outside the repository and deliverable folder.' }
    $keygen = Resolve-BridgeTool ssh-keygen
    $argv = @('-t','ed25519','-f',$key,'-C','pwsh-ssh-bridge')
    if ($Unattended) {
        # Explicit opt-in: empty passphrase for unattended work, protected by OS file permissions.
        $argv += @('-N','')
        $result = Invoke-BridgeProcess $keygen $argv -TimeoutSeconds 30
        if ($result.ExitCode -ne 0) { throw "Key generation failed: $($result.Err.Text)" }
    } else {
        # Human-owned terminal only: passphrase stays in ssh-keygen's prompt.
        & $keygen @argv
        if ($LASTEXITCODE -ne 0) { throw 'Interactive key generation failed.' }
    }
    if ($IsWindows) {
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = Get-Acl -LiteralPath $key
        $acl.SetAccessRuleProtection($true,$false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($rule) }
        $acl.SetOwner($sid)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow'))
        Set-Acl -LiteralPath $key -AclObject $acl
    } else {
        & chmod 600 $key
        if ($LASTEXITCODE -ne 0) { throw 'Could not restrict private-key permissions.' }
    }
    [ordered]@{schemaVersion=1; operation='keygen'; outcome='created'; privateKeyPath=$key; publicKeyPath="$key.pub"; passphraseProtected=(-not $Unattended)} | ConvertTo-Json -Compress
} catch {
    Write-BridgeFailure 'keygen' $_.Exception.Message
    exit 2
}
