#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts/Bridge.Common.psm1') -Force
$work = [IO.Path]::GetFullPath($WorkDirectory)
if ($work.StartsWith([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $work -eq $root) { throw 'Keep test credentials outside the source tree.' }
$run = Join-Path $work ('local-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($run) | Out-Null
$pwsh = (Get-Process -Id $PID).Path
$passed = [Collections.Generic.List[string]]::new()
function Assert([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $passed.Add($Name)
}
function Run-Script([string]$Name,[string[]]$Arguments) {
    Invoke-BridgeProcess $pwsh (@('-NoProfile','-File',(Join-Path $root "scripts/$Name")) + $Arguments) -TimeoutSeconds 30
}
foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -File) {
    $errors=$null; $tokens=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) "parse:$($file.Name)"
}
$literal = 'spaces "quotes" ''apostrophe'' $HOME $(touch nope); 中文 😀' + "`n"
$echoed = Invoke-BridgeProcess $pwsh @('-NoProfile','-Command','[Console]::Out.Write([Console]::In.ReadToEnd()); [Console]::Error.Write("err"); exit 7') -InputText $literal
Assert ($echoed.Out.Text -ceq $literal -and $echoed.Err.Text -eq 'err' -and $echoed.ExitCode -eq 7) 'stdin/UTF-8/metacharacters/separate-stderr/exit-code'
$large = Invoke-BridgeProcess $pwsh @('-NoProfile','-Command','[Console]::Out.Write("a" * 200000); [Console]::Error.Write("b" * 200000)') -MaxOutputChars 1024
Assert ($large.Out.Text.Length -eq 1024 -and $large.Err.Text.Length -eq 1024 -and $large.Out.TotalChars -eq 200000 -and $large.Err.TotalChars -eq 200000) 'bounded-output-drains-both-streams'
$slow = Invoke-BridgeProcess $pwsh @('-NoProfile','-Command','Start-Sleep -Seconds 10') -TimeoutSeconds 1
$unknown = ConvertTo-BridgeResult $slow 'exec' 'lab'
Assert ($slow.TimedOut -and $unknown.outcome -eq 'unknown' -and -not $unknown.automaticRetry) 'deadline-yields-unknown-without-replay'
$exit255 = Invoke-BridgeProcess $pwsh @('-NoProfile','-Command','exit 255')
Assert ((ConvertTo-BridgeResult $exit255 'exec' 'lab').outcome -eq 'unknown') 'exit-255-is-conservative'
$keyPath = Join-Path $run 'fixture_ed25519'
$key = Run-Script 'New-BridgeKey.ps1' @('-Path',$keyPath,'-Unattended')
Assert ($key.ExitCode -eq 0 -and (Test-Path "$keyPath.pub")) 'dedicated-key-created'
$before = (Get-FileHash -LiteralPath $keyPath).Hash
$again = Run-Script 'New-BridgeKey.ps1' @('-Path',$keyPath,'-Unattended')
Assert ($again.ExitCode -eq 2 -and (Get-FileHash -LiteralPath $keyPath).Hash -eq $before) 'existing-key-preserved'
if ($IsWindows) {
    $acl=Get-Acl -LiteralPath $keyPath
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $foreign=@($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $sid })
    Assert ($acl.AreAccessRulesProtected -and $foreign.Count -eq 0) 'private-key-ACL-restricted-to-creator'
}
$fp=Invoke-BridgeProcess (Resolve-BridgeTool ssh-keygen) @('-lf',"$keyPath.pub",'-E','sha256')
$fingerprint=($fp.Out.Text.Trim() -split '\s+')[1]
$profile = Join-Path $run 'profile with spaces'
$argsProfile=@('-Directory',$profile,'-Alias','lab','-HostName','192.0.2.40','-Port','22022','-UserName','operator','-IdentityFile',$keyPath,'-HostPublicKeyFile',"$keyPath.pub",'-ExpectedFingerprint',$fingerprint)
$created = Run-Script 'New-BridgeProfile.ps1' $argsProfile
Assert ($created.ExitCode -eq 0) 'verified-host-profile-created'
$config=Join-Path $profile 'ssh_config'
$resolved=Invoke-BridgeProcess (Resolve-BridgeTool ssh) @('-F',$config,'-G','lab')
Assert ($resolved.ExitCode -eq 0 -and $resolved.Out.Text -match '(?m)^stricthostkeychecking true\r?$' -and $resolved.Out.Text -match '(?m)^port 22022\r?$') 'OpenSSH-resolves-generated-profile'
$refuseProfile=Run-Script 'New-BridgeProfile.ps1' $argsProfile
Assert ($refuseProfile.ExitCode -eq 2) 'existing-profile-refused'
$argsBad=$argsProfile.Clone(); $argsBad[1]=Join-Path $run 'bad-profile'; $argsBad[-1]='SHA256:' + ('A' * 43)
$mismatch=Run-Script 'New-BridgeProfile.ps1' $argsBad
Assert ($mismatch.ExitCode -eq 2 -and -not (Test-Path $argsBad[1])) 'fingerprint-mismatch-refused-before-profile-write'
$console=Join-Path $run 'console.sh'
$generated=Run-Script 'New-ConsoleSetup.ps1' @('-PublicKeyFile',"$keyPath.pub",'-TargetUser','operator','-OutputFile',$console)
Assert ($generated.ExitCode -eq 0 -and -not ([IO.File]::ReadAllText($console).Contains("`r"))) 'console-script-generated-with-LF'
$invalid=Run-Script 'Invoke-Bridge.ps1' @('-ConfigFile',$config,'-Alias','-oProxyCommand=bad','-Probe')
Assert ($invalid.ExitCode -eq 2 -and ($invalid.Out.Text | ConvertFrom-Json).outcome -eq 'local_error') 'option-injection-alias-rejected'
$missing=Run-Script 'Invoke-Bridge.ps1' @('-ConfigFile',$config,'-Alias','lab','-ScriptPath',(Join-Path $run 'absent.sh'))
Assert ($missing.ExitCode -eq 2 -and ($missing.Out.Text | ConvertFrom-Json).outcome -eq 'local_error') 'missing-script-rejected-before-network'
$copy=Run-Script 'Copy-BridgeFile.ps1' @('-Direction','Download','-ConfigFile',$config,'-Alias','lab','-LocalPath',(Join-Path $run 'download.bin'),'-RemotePath','/tmp/*','-AllowDestinationOverwrite')
Assert ($copy.ExitCode -eq 2) 'remote-wildcard-copy-refused'
[ordered]@{outcome='passed'; count=$passed.Count; tests=$passed; scratchDirectory=$run} | ConvertTo-Json -Depth 4
