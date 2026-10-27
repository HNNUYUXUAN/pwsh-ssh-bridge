#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigFile,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][string]$WorkDirectory
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts/Bridge.Common.psm1') -Force
$work=[IO.Path]::GetFullPath($WorkDirectory)
if ($work.StartsWith([IO.Path]::GetFullPath($root) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $work -eq $root) { throw 'Use a private scratch directory outside the source tree.' }
$run=Join-Path $work ('live-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($run) | Out-Null
$pwsh=(Get-Process -Id $PID).Path
$passed=[Collections.Generic.List[string]]::new()
function Assert([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $passed.Add($Name) }
function Call-Helper([string]$Name,[string[]]$Arguments) {
    $r=Invoke-BridgeProcess $pwsh (@('-NoProfile','-File',(Join-Path $root "scripts/$Name")) + $Arguments) -TimeoutSeconds 90
    if (-not $r.Out.Text.Trim()) { throw "No JSON from $Name. $($r.Err.Text)" }
    $data=$r.Out.Text | ConvertFrom-Json
    return @{process=$r; data=$data}
}
function Remote([string]$Text,[int]$Deadline=30) {
    $path=Join-Path $run ([guid]::NewGuid().ToString('N') + '.sh')
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
    Call-Helper 'Invoke-Bridge.ps1' @('-ConfigFile',$ConfigFile,'-Alias',$Alias,'-ScriptPath',$path,'-TimeoutSeconds',"$Deadline")
}
$remoteDir=$null
$tunnel=$null
try {
    $probe=Call-Helper 'Invoke-Bridge.ps1' @('-ConfigFile',$ConfigFile,'-Alias',$Alias,'-Probe')
    if ($probe.data.outcome -ne 'completed') { Write-Output ($probe.data | ConvertTo-Json -Compress) }
    Assert ($probe.data.outcome -eq 'completed' -and $probe.data.stdout -match 'bridge_probe=ok') 'authenticated-probe'
    $echoScript=@'
cat <<'BRIDGE_LITERAL'
中文 😀 "quotes" 'apostrophe' $HOME $(uname)
BRIDGE_LITERAL
printf err >&2
exit 7
'@
    $echo=Remote ($echoScript.Replace("`r`n","`n").Replace("`n","`r`n") + "`r`n")
    if ($echo.process.ExitCode -ne 7 -or -not $echo.data.stdout.Contains('中文 😀') -or $echo.data.stderr -ne 'err') { Write-Output ($echo.data | ConvertTo-Json -Compress) }
    Assert ($echo.process.ExitCode -eq 7 -and $echo.data.stdout.Contains('中文 😀') -and $echo.data.stdout.Contains('$(uname)') -and $echo.data.stdout.Contains("'apostrophe'") -and $echo.data.stderr -eq 'err') 'remote-UTF-8-CRLF-quotes-and-exit-status'
    $made=Remote 'mktemp -d /tmp/pwsh-ssh-bridge-test.XXXXXXXX'
    $remoteDir=$made.data.stdout.Trim()
    Assert ($made.data.outcome -eq 'completed' -and $remoteDir -match '^/tmp/pwsh-ssh-bridge-test\.[A-Za-z0-9]+$') 'isolated-remote-test-directory'
    $payload=Join-Path $run 'payload with spaces.bin'
    $bytes=New-Object byte[] 65537
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    [IO.File]::WriteAllBytes($payload,$bytes)
    $remoteFile="$remoteDir/payload with spaces.bin"
    $upload=Call-Helper 'Copy-BridgeFile.ps1' @('-Direction','Upload','-ConfigFile',$ConfigFile,'-Alias',$Alias,'-LocalPath',$payload,'-RemotePath',$remoteFile,'-AllowDestinationOverwrite')
    Assert ($upload.data.outcome -eq 'completed') 'SFTP-binary-upload-with-spaces'
    $download=Join-Path $run 'download with spaces.bin'
    $fetched=Call-Helper 'Copy-BridgeFile.ps1' @('-Direction','Download','-ConfigFile',$ConfigFile,'-Alias',$Alias,'-LocalPath',$download,'-RemotePath',$remoteFile,'-AllowDestinationOverwrite')
    Assert ($fetched.data.outcome -eq 'completed' -and (Get-FileHash $payload).Hash -eq (Get-FileHash $download).Hash) 'SFTP-binary-roundtrip-hash'
    $slow=Remote 'sleep 3; printf finished' 1
    Assert ($slow.process.ExitCode -eq 124 -and $slow.data.outcome -eq 'unknown' -and -not $slow.data.automaticRetry) 'live-timeout-without-automatic-retry'
    # Synthetic account database confines installation tests to the temporary directory.
    $keyPath=Join-Path $run 'fixture_ed25519'
    $key=Call-Helper 'New-BridgeKey.ps1' @('-Path',$keyPath,'-Unattended')
    Assert ($key.data.outcome -eq 'created') 'bootstrap-fixture-key'
    $wrongHosts=Join-Path $run 'wrong_known_hosts'
    $fixturePub=([IO.File]::ReadAllText("$keyPath.pub").Trim() -split '\s+')[0..1] -join ' '
    [IO.File]::WriteAllText($wrongHosts, "* $fixturePub`n", [Text.UTF8Encoding]::new($false))
    $badConfig=Join-Path $run 'wrong_host_config'
    $badHeader="Host $Alias`n    UserKnownHostsFile " + (ConvertTo-BridgeConfigPath $wrongHosts) + "`n    GlobalKnownHostsFile none`n"
    [IO.File]::WriteAllText($badConfig, $badHeader + [IO.File]::ReadAllText((Get-BridgeFile $ConfigFile)), [Text.UTF8Encoding]::new($false))
    $wrongIdentity=Call-Helper 'Invoke-Bridge.ps1' @('-ConfigFile',$badConfig,'-Alias',$Alias,'-Probe')
    Assert ($wrongIdentity.process.ExitCode -ne 0 -and $wrongIdentity.data.stderr -match 'HOST IDENTIFICATION HAS CHANGED|Host key verification failed' -and $wrongIdentity.data.stdout -notmatch 'bridge_probe=ok') 'changed-host-key-blocks-live-execution'
    $setup=Join-Path $run 'setup.sh'
    $gen=Call-Helper 'New-ConsoleSetup.ps1' @('-PublicKeyFile',"$keyPath.pub",'-TargetUser','bridge_fixture','-OutputFile',$setup)
    Assert ($gen.data.outcome -eq 'created') 'bootstrap-console-script'
    $put=Call-Helper 'Copy-BridgeFile.ps1' @('-Direction','Upload','-ConfigFile',$ConfigFile,'-Alias',$Alias,'-LocalPath',$setup,'-RemotePath',"$remoteDir/setup.sh",'-AllowDestinationOverwrite')
    Assert ($put.data.outcome -eq 'completed') 'bootstrap-script-upload'
    $fixture=@'
set -eu
d='__DIR__'
mkdir "$d/bin" "$d/home"
cat > "$d/bin/getent" <<'GETENT'
#!/bin/sh
printf 'bridge_fixture:x:%s:%s::%s:/bin/sh\n' "$(id -u)" "$(id -g)" "$BRIDGE_FIXTURE_HOME"
GETENT
chmod 700 "$d/bin/getent"
export BRIDGE_FIXTURE_HOME="$d/home"
export PATH="$d/bin:$PATH"
sh -n "$d/setup.sh"
sh "$d/setup.sh" >/dev/null
before=$(sha256sum "$d/home/.ssh/authorized_keys" | cut -d' ' -f1)
sh "$d/setup.sh" >/dev/null
after=$(sha256sum "$d/home/.ssh/authorized_keys" | cut -d' ' -f1)
test "$before" = "$after"
test "$(stat -c %a "$d/home/.ssh")" = 700
test "$(stat -c %a "$d/home/.ssh/authorized_keys")" = 600
printf bootstrap_idempotence_ok
'@
    $boot=Remote $fixture.Replace('__DIR__',$remoteDir)
    Assert ($boot.data.outcome -eq 'completed' -and $boot.data.stdout -eq 'bootstrap_idempotence_ok') 'console-install-idempotence-and-permissions-in-fixture'
    # Reserve an available loopback port, then release it for ssh. Bind failures are explicit.
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
    $listener.Start(); $port=$listener.LocalEndpoint.Port; $listener.Stop()
    $start=[Diagnostics.ProcessStartInfo]::new($pwsh)
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach($a in @('-NoProfile','-File',(Join-Path $root 'scripts/Open-BridgeTunnel.ps1'),'-ConfigFile',$ConfigFile,'-Alias',$Alias,'-LocalPort',"$port",'-RemoteHost','127.0.0.1','-RemotePort','22')) { $start.ArgumentList.Add($a) }
    $tunnel=[Diagnostics.Process]::Start($start)
    $tunnelOut=$tunnel.StandardOutput.ReadToEndAsync(); $tunnelErr=$tunnel.StandardError.ReadToEndAsync()
    $banner=''
    for ($attempt=0; $attempt -lt 15; $attempt++) {
        if ($tunnel.HasExited) { throw "Tunnel exited: $($tunnelErr.GetAwaiter().GetResult())" }
        $tcp=[Net.Sockets.TcpClient]::new()
        try {
            if ($tcp.ConnectAsync('127.0.0.1',$port).Wait(500)) {
                $tcp.GetStream().ReadTimeout=3000
                $reader=[IO.StreamReader]::new($tcp.GetStream())
                $banner=$reader.ReadLine()
                break
            }
        } catch { Start-Sleep -Milliseconds 200 }
        finally { $tcp.Dispose() }
    }
    Assert ($banner -match '^SSH-2.0-') 'loopback-forward-serves-remote-SSH-banner'
    $occupied=Invoke-BridgeProcess $pwsh @('-NoProfile','-File',(Join-Path $root 'scripts/Open-BridgeTunnel.ps1'),'-ConfigFile',$ConfigFile,'-Alias',$Alias,'-LocalPort',"$port",'-RemoteHost','127.0.0.1','-RemotePort','22') -TimeoutSeconds 15
    Assert (-not $occupied.TimedOut -and $occupied.ExitCode -ne 0) 'occupied-tunnel-port-fails-explicitly'
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { $tunnel.Kill($true); $tunnel.WaitForExit() }
    if ($remoteDir -and $remoteDir -match '^/tmp/pwsh-ssh-bridge-test\.[A-Za-z0-9]+$') {
        # Delete only explicit fixture files; rmdir refuses unexpected content.
        $cleanup=Remote ("set -eu`nd='$remoteDir'`n" + 'rm -f -- "$d/payload with spaces.bin" "$d/setup.sh" "$d/bin/getent" "$d/home/.ssh/authorized_keys"' + "`nrmdir -- " + '"$d/home/.ssh" "$d/home" "$d/bin" "$d"' + "`n")
        if ($cleanup.data.outcome -ne 'completed') { Write-Warning "Fixture cleanup incomplete: $remoteDir" }
    }
}
[ordered]@{outcome='passed'; count=$passed.Count; tests=$passed; scratchDirectory=$run} | ConvertTo-Json -Depth 4
