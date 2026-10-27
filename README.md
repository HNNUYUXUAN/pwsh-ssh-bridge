# PowerShell SSH Bridge

[简体中文](README.zh-CN.md)

An Agent Skill that lets a local coding agent operate a Linux machine through
PowerShell and OpenSSH. It guides first-time setup, checks what is actually installed,
verifies server identity, diagnoses network failures, and provides small executable helpers.

```text
Local Codex session → PowerShell 7 → OpenSSH → Linux sshd → authorized command
```

The remote machine needs an SSH server and shell; the agent harness and its login
stay on the local computer. Users can bootstrap through an existing VS Code SSH
terminal, an ordinary SSH terminal, or a provider's trusted console.

## Supported and verified scope

The validation target is **Codex on Windows → PowerShell 7 → Windows OpenSSH → Linux**.
The prose uses capability-based instructions so another harness can adapt the workflow.
Each additional harness/platform needs its own command-tool, permissions, quoting and
runtime tests. See [verification](references/verification.md) for the exact tested state.

“Bridge” means orchestrating SSH from the local agent. The optional forwarding helper
creates an actual SSH `-L` tunnel. Successful SSH still requires an authorized reachable
route: a private network, a public mapping, or a separately provisioned access path.

## Install in Codex

Download the `*-skill.zip` and `SHA256SUMS` from
[Releases](https://github.com/HNNUYUXUAN/pwsh-ssh-bridge/releases). Compare the ZIP's
SHA256 using `Get-FileHash -Algorithm SHA256`, extract into a new directory, and review
the files. The ZIP contains a `pwsh-ssh-bridge` folder. Copy that folder to your host's
reported user skill root (for example `$HOME/.agents/skills`). Preserve an existing
installation before replacing it; avoid duplicate skills with the same name.

For installation from a reviewed source checkout, use Python 3.10+:

```powershell
python dev/install.py --destination "$HOME/.agents/skills/pwsh-ssh-bridge"
```

The installer requires a new destination and copies the runtime inventory only.
The development guide explains upgrades and alternate host skill directories.

Invoke explicitly:

> Use $pwsh-ssh-bridge to connect my Linux machine. Inspect my local setup first,
> reuse any approved connection details, and tell me which terminal to use for each step.

Codex detects skills automatically; restart if the skill does not appear. Existing
installations may expose a different skill root; use the root reported by that host.
Avoid duplicate copies with the same name. [Official skill documentation](https://developers.openai.com/codex/skills).

## Start here

1. Agent: read [SKILL.md](SKILL.md).
2. First connection: follow [setup](references/setup.md), including the access-route choices.
3. Established connection: use [operations](references/operations.md).
4. Failed step: use [troubleshooting](references/troubleshooting.md).
5. Understand the approach: read the [real case, anonymized](references/case-study.md)
   and [research and attribution](references/research.md).

All substantive guides have complete Chinese counterparts linked at their top.

## Design

- Observe before configuring; report the effective local identity and actual tools.
- Verify host identity through an independent trusted channel.
- Send remote scripts via stdin to preserve quoting and UTF-8 text.
- Return bounded structured results with explicit timeout/unknown outcomes.
- Keep credentials local and reuse supported harness permission mechanisms.
- Reconnect on demand; verify operations rather than promising indefinite connectivity.

The helpers are intentionally small. They leave account selection, target scope, service
changes, and authorization to the user's task. Local forwarding stays on loopback.
Transfers require an explicit overwrite flag and should target a unique staging filename.

## Complete development workspace

Clone this repository or download the matching `*-workspace.zip` from Releases.
The default branch includes all runtime source, tests, bilingual guides, agent handoff
instructions, build tooling and CI. An agent can edit, validate, rebuild and locally
install the skill from this checkout.

```sh
git clone https://github.com/HNNUYUXUAN/pwsh-ssh-bridge.git
cd pwsh-ssh-bridge
python dev/build.py --check
python -m unittest discover -s dev -p 'test_*.py' -v
python dev/build.py
```

Python 3.10+ uses only the standard library. Runtime checks require PowerShell 7.2+
and OpenSSH. Both ZIPs plus SHA256 checksums appear in `dist/`.
Read the [development guide](https://github.com/HNNUYUXUAN/pwsh-ssh-bridge/blob/main/docs/development.md)
for the source map, tests, installation, releases and agent handoff. Runtime-only
installations can obtain the matching workspace when the user asks to extend the skill.

## License

[MIT](LICENSE). External implementations were studied for design decisions; this repository
contains independently written code and documents. Referenced projects retain their own licenses.
