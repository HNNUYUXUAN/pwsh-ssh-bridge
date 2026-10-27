#Requires -Version 7.2
[CmdletBinding(DefaultParameterSetName='Probe')]
param(
    [Parameter(Mandatory)][string]$ConfigFile,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(ParameterSetName='Probe')][switch]$Probe,
    [Parameter(Mandatory,ParameterSetName='File')][string]$ScriptPath,
    [Parameter(Mandatory,ParameterSetName='Command')][string]$Command,
    [ValidateRange(1,86400)][int]$TimeoutSeconds=60,
    [ValidateRange(1024,1048576)][int]$MaxOutputChars=65536
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Bridge.Common.psm1') -Force
$operation = if ($PSCmdlet.ParameterSetName -eq 'Probe') { 'probe' } else { 'exec' }
try {
    $inputText = switch ($PSCmdlet.ParameterSetName) {
        'File' { [IO.File]::ReadAllText((Get-BridgeFile $ScriptPath), [Text.UTF8Encoding]::new($false,$true)) }
        'Command' { $Command }
        default { "set -eu`nprintf 'bridge_probe=ok\n'`nid`nhostname`nuname -sr`n" }
    }
    if ($inputText.Contains([char]0)) { throw 'Remote shell input contains a NUL character.' }
    # Only script text is normalized; file transfers remain byte-for-byte copies.
    $inputText = $inputText.Replace("`r`n","`n")
    if (-not $inputText.EndsWith("`n")) { $inputText += "`n" }
    $argv = @(Get-BridgeSshArguments $ConfigFile $Alias) + @('sh','-s')
    $result = Invoke-BridgeProcess -Executable (Resolve-BridgeTool ssh) -Arguments $argv -InputText $inputText -TimeoutSeconds $TimeoutSeconds -MaxOutputChars $MaxOutputChars
    ConvertTo-BridgeResult $result $operation $Alias | ConvertTo-Json -Compress -Depth 5
    if ($result.TimedOut) { exit 124 }
    exit $result.ExitCode
} catch {
    Write-BridgeFailure $operation $_.Exception.Message
    exit 2
}
