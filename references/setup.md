# First connection: both ends

[简体中文](setup.zh-CN.md)

Use this guide from the first incomplete checkpoint. Tell the user which computer
and terminal each command belongs to. Replace examples before presenting commands.
Keep a completed step complete unless new evidence invalidates it.

## 1. Establish what the agent can do

Ask only for missing facts: target login command/account, available remote access,
and whether the local agent can run commands. Reuse relevant authorized memory,
conversation evidence, existing SSH aliases and the user's terminal preference.
Revalidate remembered addresses and fingerprints; never treat memory as credentials.

If command tools are absent, explain the prerequisite in plain language:
“This chat can prepare commands. To run them automatically, open a local agent
session that can use your computer's terminal.” Continue with human-run commands.

Identify the actual local shell. Git Bash uses `/c/...` paths; PowerShell uses Windows
paths. From Git Bash, `pwsh -NoProfile -File 'C:/path/to/script.ps1' ...` launches the
helper without changing the user's preferred terminal. If the harness reports a different
shell than the one that runs the command, inspect a minimal version/identity command;
do not stack shell wrappers until something appears to work.

### Local Windows prerequisites

If PowerShell 7 is not known to exist, use an ordinary Windows PowerShell terminal:

```powershell
$PSVersionTable.PSVersion
Get-Command pwsh, ssh, ssh-keygen, scp -ErrorAction SilentlyContinue | Select-Object Name, Source
```

Success: `pwsh` exists and reports version 7.2 or newer; OpenSSH is available.
If PowerShell 7 is missing, offer installation through the user's approved software
channel. Where WinGet is available, the user can install it with
`winget install --id Microsoft.PowerShell --exact`, then open a new terminal.
On managed computers, use the administrator's package instead of changing policy.

For missing Windows OpenSSH, inspect the optional feature in an elevated Windows
PowerShell terminal and install the **client** if authorized:

```powershell
Get-WindowsCapability -Online -Name 'OpenSSH.Client*'
Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0'
```

This adds the client on the local computer. The Linux SSH server is a separate component.
Then run `scripts/Test-BridgeEnvironment.ps1` in PowerShell 7. The JSON report records
the effective Windows identity, executable paths and SSH version. `networkTested=false`
means exactly that: this step has not established remote connectivity.

### Credentials and sandbox identity

The harness may execute as a sandbox identity rather than the user's interactive
Windows identity. An “Access denied” on a saved `.ssh` config/key is a local access
failure, even if a later line also says “not found.” Use the harness's permission
request for that existing key/config and the intended network access. Do not broaden
the private key's ACL to a sandbox group or copy it into repository outputs.

Review an unfamiliar SSH config before passing it to tools: `ProxyCommand`, `Match exec`
and included files can execute local commands. A reviewed existing profile is reusable.

## 2. Find a trusted remote terminal

Offer these choices, with instructions matched to the answer:

| Available access | What to do |
|---|---|
| VS Code already connected using Remote-SSH | Open **Terminal → New Terminal** in that remote window; run `hostname; id; pwd` to confirm it is Linux |
| An ordinary SSH client is already logged in | Keep that authenticated terminal open and run the same identity check |
| Cloud browser console or graphical Linux desktop | Open its terminal; run the identity check |
| No authenticated terminal or trusted provider channel | Use the provider's recovery console or administrator to establish access first |

VS Code's terminal might be local even when another window is remote. Verify the
hostname and `id` output. A Windows prompt such as `PS C:\...>` belongs to the local end.
An existing VS Code `Host` alias may involve `ProxyJump`, an agent or a different key;
inspect and reuse its relevant configuration rather than assuming the public IP works directly.

Keep passwords in the human's terminal. Do not ask them to paste a password or private key
into the conversation. If no initial trusted access exists, provide the exact provider
action needed; a local helper cannot manufacture remote authorization.

### Linux readiness and privilege

In the trusted Linux terminal:

```sh
hostname
id
command -v sh
command -v getent
ss -lnt
```

The console helper needs Linux `getent`, `awk`, `cut`, and standard file tools. If a
minimal distribution lacks these, explain the missing dependency and prepare a reviewed
manual procedure for that OS. Do not invent a home directory or force root access.

If SSH is already working through VS Code or another terminal, the server is present.
Otherwise inspect `sshd` and service status using the distribution's service manager.
For an Ubuntu/Debian target where installing an SSH server is authorized, guide the user:

```sh
sudo apt-get update
sudo apt-get install openssh-server
sudo systemctl enable --now ssh
```

Recheck the listener. Cloud public ports can differ from the Linux listener's port.
Do not change the Linux port to match the public mapping without understanding the mapping.
Other distributions need their own package/service instructions.

Choose the login account explicitly. If the console account differs from the target
account, installation needs the target account's session or authorized `sudo` access.
For example, an ordinary account cannot write `/root/.ssh/authorized_keys`.

## 3. Reuse or create the login key locally

Prefer a suitable key already approved for this host. If a new key is needed, explain:

- **Passphrase + ssh-agent:** the human unlocks the key in their local terminal; subsequent
  batch calls need access to that same agent context.
- **Dedicated unattended key:** no passphrase; access is protected by the local account
  and key ACL. Use only when the user chooses unattended operation.

Create a private credential directory outside repositories and deliverables. In PowerShell:

```powershell
$credentialDir = Join-Path $HOME '.ssh/agent-bridge-lab'
New-Item -ItemType Directory -Path $credentialDir -Force | Out-Null
& '<skill-root>/scripts/New-BridgeKey.ps1' -Path (Join-Path $credentialDir 'login_ed25519')
```

That command prompts for a passphrase and belongs in a human-owned interactive terminal.
For the user's selected unattended mode, add `-Unattended`; the script emits JSON and
restricts the new private file to the creating account. Existing keys are never replaced.
If permission restriction fails after generation, the script reports failure: inspect the
created file before continuing; do not call the result ready.

For an encrypted key on Windows, inspect `Get-Service ssh-agent`. If the user chooses
to enable a stopped/disabled service, use their authorized elevated terminal to configure
and start it. Then run `ssh-add '<private-key-path>'` interactively. Agent visibility is
identity-dependent; validate through the actual harness execution context.

## 4. Prepare and install only the login public key

Locally, generate instructions with the selected remote username:

```powershell
& '<skill-root>/scripts/New-ConsoleSetup.ps1' `
  -PublicKeyFile '<private-key-path>.pub' -TargetUser operator `
  -OutputFile '<private-work-directory>/install-public-key.sh'
```

Read the generated script. It identifies the account's actual home, checks privilege,
preserves existing keys (including restrictions on an existing matching key), refuses
symlinked SSH files, and prints `PUBLIC_KEY_INSTALLED` on success.

For a user who can save a remote file, use VS Code's remote editor or their existing
transfer channel to save it on Linux, then run `sh /path/install-public-key.sh` as the
target account, or `sudo sh /path/install-public-key.sh` when needed and authorized.

For paste-only access, show **the full generated content** inside a quoted heredoc:

```sh
sh <<'BRIDGE_SETUP'
# Replace this line with the complete generated script before showing it to the user.
BRIDGE_SETUP
```

Use `sudo sh` for an authorized different target account. Do not send the placeholder
above as the actual user command. Sudo passwords remain in that terminal. If pasted
text acquires `^[[200~` or a trailing `~`, clear the line and paste a clean block again.

Success marker: `PUBLIC_KEY_INSTALLED user=<chosen-user>`.
An error is not success even if later diagnostic commands work.

## 5. Obtain and pin the server's host identity

In the **trusted Linux terminal**, collect:

```sh
cat /etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

Use `sudo` only if reading these public files needs it. These are public host identity
data, distinct from the login key installed in step 4. Never read the corresponding
private host key. If the server has no Ed25519 host key, inspect its supported algorithms
and use a reviewed manual OpenSSH profile; the profile helper validates Ed25519 only.

Save just the `ssh-ed25519 ...` public-key line in a local text file. Supply the reported
`SHA256:...` fingerprint separately to the profile helper. If using `ssh-keyscan` to gather
a network key instead, compare it against this trusted-console fingerprint first.
[OpenSSH explains why keyscan output alone cannot authenticate a server](https://man.openbsd.org/ssh-keyscan).

```powershell
& '<skill-root>/scripts/New-BridgeProfile.ps1' `
  -Directory '<private-directory>/profile' -Alias lab `
  -HostName '192.0.2.40' -Port 22022 -UserName operator `
  -IdentityFile '<private-key-path>' `
  -HostPublicKeyFile '<private-work-directory>/host-ed25519.pub' `
  -ExpectedFingerprint 'SHA256:<actual-fingerprint>'
```

Replace all example values. The helper creates a dedicated config and known-hosts file,
pins a stable host identity alias, and rejects mismatches/existing profile directories.
It references the key in place. Profile creation does not yet prove connectivity.

## 6. Probe and choose the verified route

```powershell
& '<skill-root>/scripts/Invoke-Bridge.ps1' `
  -ConfigFile '<private-directory>/profile/ssh_config' -Alias lab -Probe
```

Success requires `outcome=completed`, exit code 0, `bridge_probe=ok`, and the expected
hostname/account. Confirm these match the user's intended machine. A reachable port,
provider UI status, or installed public key alone is insufficient.

If a public mapping fails, consult [troubleshooting](troubleshooting.md). Ask for or
observe the target's private address through trusted evidence. Try only confirmed routes.
When changing address/port for the same device, retain the verified host key and its
HostKeyAlias. Save the config change after a successful probe. Use a bastion only when
the user has authorized it; keep its separate host identity verified as well.

## 7. Make reconnecting easy

Record privately: alias, config path, current route, username, verified fingerprint,
observed hostname, last successful time, and authorization scope. Use a harness memory
facility if it exists and is authorized, or the user's chosen local note. Record a
reconnection command using `-Probe`; no passwords or key contents belong in this note.

After reboot, rerun the probe. If an address/port changed, confirm the new endpoint and
retain host identity verification. Keep the console open until the new path succeeds.
