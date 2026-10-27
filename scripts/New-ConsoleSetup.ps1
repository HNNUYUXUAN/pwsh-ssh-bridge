#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PublicKeyFile,
    [Parameter(Mandatory)][string]$TargetUser,
    [Parameter(Mandatory)][string]$OutputFile
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
try {
    if ($TargetUser -notmatch '^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$') { throw 'Invalid Linux account name.' }
    $line = [IO.File]::ReadAllText((Get-BridgeFile $PublicKeyFile)).Trim()
    if ($line -notmatch '^ssh-ed25519 ([A-Za-z0-9+/]+={0,2})(?: [^\r\n]*)?$') { throw 'Expected a single Ed25519 public-key line.' }
    $blob = $Matches[1]
    $out = [IO.Path]::GetFullPath($OutputFile)
    if (Test-Path -LiteralPath $out) { throw 'Output file already exists; choose a new path.' }
    $template = @'
#!/bin/sh
set -eu
target='__USER__'
key='ssh-ed25519 __KEY__ pwsh-ssh-bridge'
entry=$(getent passwd "$target") || { echo 'Target account does not exist.' >&2; exit 1; }
target_uid=$(printf '%s\n' "$entry" | cut -d: -f3)
target_gid=$(printf '%s\n' "$entry" | cut -d: -f4)
target_home=$(printf '%s\n' "$entry" | cut -d: -f6)
case "$target_home" in /*) ;; *) echo 'Invalid target home.' >&2; exit 1 ;; esac
current_uid=$(id -u)
if [ "$current_uid" != 0 ] && [ "$current_uid" != "$target_uid" ]; then
  echo 'Run this file as the target account, or use sudo sh FILE when authorized.' >&2
  exit 1
fi
ssh_dir="$target_home/.ssh"
keys="$ssh_dir/authorized_keys"
if [ -L "$ssh_dir" ] || [ -L "$keys" ]; then
  echo 'SSH path is a symlink; inspect it manually before installing a key.' >&2
  exit 1
fi
umask 077
mkdir -p "$ssh_dir"
touch "$keys"
# Do not add an unrestricted duplicate if this key already has restrictions.
if ! awk -v expected='__KEY__' '{ for(i=1;i<NF;i++) if($i=="ssh-ed25519" && $(i+1)==expected) found=1 } END { exit !found }' "$keys"; then
  printf '\n%s\n' "$key" >> "$keys"
fi
chmod 700 "$ssh_dir"
chmod 600 "$keys"
if [ "$current_uid" = 0 ]; then
  chown "$target_uid:$target_gid" "$ssh_dir" "$keys"
fi
if command -v restorecon >/dev/null 2>&1; then restorecon "$ssh_dir" "$keys"; fi
printf 'PUBLIC_KEY_INSTALLED user=%s\n' "$target"
printf '\nRead the host public key and its fingerprint in this trusted terminal:\n'
printf '%s\n' 'cat /etc/ssh/ssh_host_ed25519_key.pub' 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256'
'@
    $text = $template.Replace('__USER__',$TargetUser).Replace('__KEY__',$blob).Replace("`r`n","`n") + "`n"
    [IO.File]::WriteAllText($out,$text,[Text.UTF8Encoding]::new($false))
    [ordered]@{schemaVersion=1; operation='console_setup'; outcome='created'; file=$out; targetUser=$TargetUser; remoteChanged=$false} | ConvertTo-Json -Compress
} catch {
    Write-BridgeFailure 'console_setup' $_.Exception.Message
    exit 2
}
