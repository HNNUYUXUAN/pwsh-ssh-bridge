# Operating a verified connection

[简体中文](operations.zh-CN.md)

Use the loaded skill directory, a reviewed config and a verified alias. Examples below
are PowerShell. Keep local work files outside the publishable source tree.

## Commands and results

For a simple read:

```powershell
& '<skill-root>/scripts/Invoke-Bridge.ps1' -ConfigFile '<profile>/ssh_config' -Alias lab -Command 'hostname; uptime'
```

For multiline code, quoting, `$`, apostrophes, backticks or Unicode, write UTF-8 text
to a local `.sh` file using the agent's file tool. Pass `-ScriptPath` rather than
embedding its content in an outer shell command. The helper runs `ssh -T ... sh -s`,
sends LF-normalized text on stdin, and closes stdin. Each call has a fresh shell;
include the intended `cd`, environment and error policy in each script.

```sh
set -eu
cd /srv/project
git status --short
```

Stdin belongs to the script transport. Commands that consume stdin can consume later
script lines; redirect their stdin explicitly or use an uploaded script and a separate
execution design when the task needs input data. Commands needing a human prompt or
sudo password should be completed in the user's trusted interactive terminal, or use
an already-authorized noninteractive sudo rule. Do not send passwords in script text.

The default shell is POSIX `sh`. For Bash-specific code, explicitly invoke Bash in the
submitted script or upload a file and invoke `bash /path/file`. The helper does not
implicitly turn every task into `set -e`; supply the error policy the task needs.

Execution results contain:

| Field | Interpretation |
|---|---|
| `schemaVersion=1` | Version of this helper's JSON contract |
| `outcome=completed` | Process returned 0; inspect expected output/postconditions too |
| `outcome=failed` | Nonzero result other than 255; inspect stderr and remote state |
| `outcome=unknown` | Timeout or exit 255; a remote action may have happened |
| `outcome=local_error` | Helper validation/runtime error; inspect the message |
| `transportExitCode` | OpenSSH/scp process exit code; SSH normally propagates the remote shell's code |
| `timedOut` | Local deadline expired; helper kills its local child process tree |
| `stdout`, `stderr` | Separate UTF-8 text, each capped by `MaxOutputChars` |
| `stdoutChars`, `stderrChars` | Observed total decoded characters before truncation |
| `outputTruncated` | Some output was discarded while streams continued draining |
| `automaticRetry=false` | Helpers never replay the operation |

The command helper defaults to a 60-second deadline and 65,536 captured characters
per stream. Tune `-TimeoutSeconds` and `-MaxOutputChars` for the task. The process exits
124 on a helper timeout, otherwise with its child exit code; 2 denotes a local helper
error. A remote program can also return 124 or 255: read JSON and context, not just the
outer number. Argument-binding errors or a missing PowerShell runtime can fail before
JSON is available. Truncated logs are evidence, not a reason to rerun a mutation.

Killing local SSH does not prove that the remote process stopped. On unknown outcome,
inspect a task-specific file, PID, job ID or service state in a separate read-only call.
Successful reconnection does not authorize automatic command replay.

## Files: stage, copy, verify, apply

The helper copies a **single file** using the SFTP default of OpenSSH 9+. It uses the
same installed OpenSSH suite as SSH and verifies host keys through the same config.
Remote paths are absolute POSIX file paths; wildcard paths and symlink/directory
targets are rejected. The preflight check is not a transaction or a concurrency lock.

Copies can overwrite a destination. The explicit `-AllowDestinationOverwrite` switch
acknowledges that behavior; the agent must obtain authorization from the actual task,
not infer authorization from the availability of the flag. Prefer a unique staging file:

```powershell
& '<skill-root>/scripts/Copy-BridgeFile.ps1' -Direction Upload `
  -ConfigFile '<profile>/ssh_config' -Alias lab `
  -LocalPath '<local-work>/config.new' -RemotePath '/tmp/task-unique/config.new' `
  -AllowDestinationOverwrite
```

Create the remote staging directory with a scoped remote command first. For downloads,
create the local parent directory, use `-Direction Download`, and choose an explicit local
filename. Local and remote paths may contain spaces. Avoid a directory destination.
The helper deliberately does not choose broad recursive transfers.

For an edit, fetch the needed file, inspect it, change it locally, show/review the diff,
upload to a unique staging path, verify its SHA256, then apply only within the task's
authorized scope. Before replacing a shared file, recheck that the original has not
changed and preserve its owner/mode and an appropriate backup. Use the project's normal
deployment mechanism when it exists. A raw copy alone does not preserve all metadata
or make deployment atomic. On a failed copy, `destinationMayBePartial=true`; verify or
remove only the known staging file before deciding how to retry.

## Actual local forwarding

Use a tunnel when a local application needs a service reachable from the Linux host.
Ordinary remote command execution does not require a listening local port.

```powershell
& '<skill-root>/scripts/Open-BridgeTunnel.ps1' `
  -ConfigFile '<profile>/ssh_config' -Alias lab `
  -LocalPort 18080 -RemoteHost 127.0.0.1 -RemotePort 8080
```

This runs foreground SSH with `-N -L` and `ExitOnForwardFailure=yes`, binding locally to
`127.0.0.1`. The remote destination is interpreted **from the SSH server**. In this
example, remote `127.0.0.1:8080` is the Linux service, while local `127.0.0.1:18080`
is the entry point on the agent's computer.

The helper's “Starting” line is not readiness proof. Check that the process remains
alive, the local port belongs to the expected SSH process, and the intended service
responds through it. A listener can succeed even when the remote service is unavailable.
Keep the harness tool session or human terminal alive; stop with Ctrl+C and verify the
port closed. If a harness starts a background Windows process, use its hidden-window
option, track that exact PID and terminate only that owned process. Do not establish
autostart, a monitor, or an indefinite daemon unless that behavior is requested.

## Jobs and reconnection

`ServerAliveInterval` detects a broken connection; it does not reconnect, restart an
agent or preserve a shell session. For long-running work, use a separately authorized
job mechanism already available on the remote device (for example a named tmux session
or project job runner). Record its identity and how to inspect it. Do not assume tmux
exists or install/start persistence automatically.

After device restart, run the authenticated probe. An address change is a routing
change; a host-key change is an identity event requiring trusted verification. Do not
delete known-host entries merely to suppress a warning.

## Bastions and outbound-only targets

The first tested route is direct SSH. A reviewed existing `ProxyJump` alias can be
reused after separately checking the bastion's credentials and host key. A jump host
does not require SSH agent forwarding for ordinary client-managed `ProxyJump` access.

If no authorized inbound path exists, explain the choices in plain language: use an
existing bastion, ask the provider for a mapping, or design an approved outbound reverse
tunnel/overlay with the network owner. Specify who owns the relay, which interface/port
is exposed, both host identities, lifecycle and cleanup before configuring it. These
topologies need their own tests; the bundled live test validates direct SSH and local `-L`.
