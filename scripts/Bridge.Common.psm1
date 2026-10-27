#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# PowerShell's redirected console may inherit a Windows OEM code page.
# JSON consumers need the same UTF-8 encoding as the SSH stream runner.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

function Resolve-BridgeTool {
    param([ValidateSet('ssh','ssh-keygen','ssh-keyscan','scp')][string]$Name)
    if ($IsWindows) {
        $native = Join-Path $env:WINDIR "System32/OpenSSH/$Name.exe"
        if (Test-Path -LiteralPath $native -PathType Leaf) { return $native }
    }
    $tool = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $tool) { throw "Missing executable: $Name. Run Test-BridgeEnvironment.ps1 and follow the setup guide." }
    return $tool.Source
}

function Get-BridgeFile {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) { throw 'Expected a file, received a directory.' }
    return $item.FullName
}

function Assert-BridgeAlias {
    param([string]$Alias)
    if ($Alias -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$') { throw 'Use a simple SSH alias: letters, numbers, dot, underscore or hyphen; start with a letter or number.' }
}

function ConvertTo-BridgeConfigPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).Replace('\','/')
    if ($full -match '[\r\n"%$]') { throw 'SSH configuration paths must not contain newline, quote, percent or dollar characters.' }
    return '"' + $full + '"'
}

function Get-BridgeSshArguments {
    param([string]$ConfigFile, [string]$Alias)
    Assert-BridgeAlias $Alias
    $config = Get-BridgeFile $ConfigFile
    # Config files can execute ProxyCommand/Match exec: inspect unfamiliar configs first.
    return @('-F', $config, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
        '-o', 'ConnectionAttempts=1', '-o', 'ConnectTimeout=10',
        '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
        '-o', 'ForwardAgent=no', '-o', 'ForwardX11=no', '-o', 'PermitLocalCommand=no',
        '-o', 'ClearAllForwardings=yes', '-T', $Alias)
}

function Initialize-BridgeRunner {
    if ('PwshSshBridge.ProcessRunner' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
namespace PwshSshBridge {
    public sealed class Capture {
        public string Text = "";
        public long TotalChars;
    }
    public sealed class ProcessResult {
        public int ExitCode;
        public bool TimedOut;
        public long ElapsedMs;
        public Capture Out;
        public Capture Err;
    }
    public static class ProcessRunner {
        static async Task<Capture> Drain(StreamReader reader, int cap) {
            var result = new Capture();
            var text = new StringBuilder();
            var buffer = new char[4096];
            int count;
            while ((count = await reader.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                result.TotalChars += count;
                int keep = Math.Min(count, Math.Max(0, cap - text.Length));
                text.Append(buffer, 0, keep);
            }
            result.Text = text.ToString();
            return result;
        }
        static async Task WriteInput(Process p, string input) {
            try { await p.StandardInput.WriteAsync(input ?? ""); }
            catch (IOException) { } // Early SSH failure closes stdin; stderr carries the failure.
            finally { try { p.StandardInput.Close(); } catch (IOException) { } }
        }
        public static async Task<ProcessResult> Run(string exe, string[] args, string input, int timeout, int cap) {
            var info = new ProcessStartInfo(exe) {
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardInputEncoding = new UTF8Encoding(false),
                StandardOutputEncoding = new UTF8Encoding(false), StandardErrorEncoding = new UTF8Encoding(false)
            };
            foreach (var arg in args) info.ArgumentList.Add(arg);
            using (var p = new Process { StartInfo = info }) {
                var watch = Stopwatch.StartNew();
                p.Start();
                var stdout = Drain(p.StandardOutput, cap);
                var stderr = Drain(p.StandardError, cap);
                var writer = WriteInput(p, input);
                var exit = p.WaitForExitAsync();
                var timer = Task.Delay(TimeSpan.FromSeconds(timeout));
                bool timedOut = await Task.WhenAny(exit, timer) != exit;
                if (timedOut && !p.HasExited) p.Kill(true);
                await exit;
                await writer;
                return new ProcessResult {
                    ExitCode = p.ExitCode, TimedOut = timedOut, ElapsedMs = watch.ElapsedMilliseconds,
                    Out = await stdout, Err = await stderr
                };
            }
        }
    }
}
'@
}

function Invoke-BridgeProcess {
    param([string]$Executable, [string[]]$Arguments, [AllowEmptyString()][string]$InputText = '',
          [ValidateRange(1,86400)][int]$TimeoutSeconds = 60,
          [ValidateRange(1024,1048576)][int]$MaxOutputChars = 65536)
    Initialize-BridgeRunner
    return [PwshSshBridge.ProcessRunner]::Run($Executable, $Arguments, $InputText, $TimeoutSeconds, $MaxOutputChars).GetAwaiter().GetResult()
}

function ConvertTo-BridgeResult {
    param($ProcessResult, [string]$Operation, [string]$Alias)
    $unknown = $ProcessResult.TimedOut -or $ProcessResult.ExitCode -eq 255
    $outcome = if ($unknown) { 'unknown' } elseif ($ProcessResult.ExitCode -eq 0) { 'completed' } else { 'failed' }
    return [ordered]@{
        schemaVersion = 1; operation = $Operation; targetAlias = $Alias
        outcome = $outcome; transportExitCode = $ProcessResult.ExitCode
        timedOut = $ProcessResult.TimedOut; elapsedMs = $ProcessResult.ElapsedMs
        stdout = $ProcessResult.Out.Text; stderr = $ProcessResult.Err.Text
        stdoutChars = $ProcessResult.Out.TotalChars; stderrChars = $ProcessResult.Err.TotalChars
        outputTruncated = ($ProcessResult.Out.TotalChars -gt $ProcessResult.Out.Text.Length -or $ProcessResult.Err.TotalChars -gt $ProcessResult.Err.Text.Length)
        automaticRetry = $false
    }
}

function Write-BridgeFailure {
    param([string]$Operation, [string]$Message)
    [ordered]@{ schemaVersion=1; operation=$Operation; outcome='local_error'; message=$Message; automaticRetry=$false } | ConvertTo-Json -Compress
}

Export-ModuleMember -Function Resolve-BridgeTool, Get-BridgeFile, Assert-BridgeAlias, ConvertTo-BridgeConfigPath, Get-BridgeSshArguments, Invoke-BridgeProcess, ConvertTo-BridgeResult, Write-BridgeFailure
