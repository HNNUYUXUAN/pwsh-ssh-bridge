# Development workspace

[简体中文](development.zh-CN.md)

The repository's default branch is the complete local development workspace.
Runtime code, instructions, tests, build tooling and research belong to the same
versioned source. Clone it when extending the skill; use the release skill ZIP for
ordinary installation. Both ZIPs are generated from this source.

## Start on a new machine

1. Install Git, Python 3.10+ and PowerShell 7.2+. Check `git --version`,
   `python --version` and `pwsh -NoProfile -Command '$PSVersionTable.PSVersion'`.
   Python uses only its standard library; there is no pip install step.
2. Clone the repository into a writable development directory:

   ```sh
   git clone https://github.com/HNNUYUXUAN/pwsh-ssh-bridge.git
   cd pwsh-ssh-bridge
   python dev/build.py --check
   python -m unittest discover -s dev -p 'test_*.py' -v
   python dev/build.py
   ```

3. For runtime development, inspect installed OpenSSH tools:

   ```powershell
   pwsh -NoProfile -File ./scripts/Test-BridgeEnvironment.ps1
   ```

   SSH runtime tests require `ssh` and `ssh-keygen`. File-transfer live tests require
   OpenSSH 9+ and server SFTP. Follow [setup](../references/setup.md) if dependencies
   are absent. Resolve sandbox/ACL errors through the harness's supported permission
   mechanism using the intended OS account.
4. Run the local suite with scratch outside the checkout:

   ```powershell
   $scratch = Join-Path ([IO.Path]::GetTempPath()) ('bridge-tests-' + [guid]::NewGuid().ToString('N'))
   pwsh -NoProfile -File ./tests/Test-Local.ps1 -WorkDirectory $scratch
   if ($LASTEXITCODE -ne 0) { throw 'Local checks failed' }
   ```

The test retains disposable keys and diagnostics under the printed scratch path.
Keep that directory private. Remove that exact directory when diagnostics are no
longer needed, after verifying the path. Build and packaging tests contact no server.

## Source map

| Path | Responsibility |
|---|---|
| `SKILL.md`, `agents/` | Agent entry point and Codex discovery metadata |
| `scripts/Bridge.Common.psm1` | Process runner, output limits, result semantics and validation |
| Other `scripts/` | Environment, credentials bootstrap, SSH profiles, execution, transfers, tunnels |
| `references/` | Complete English/Chinese setup, operations, diagnosis, research and evidence |
| `tests/` | Local behavior and opt-in Linux integration tests |
| `dev/build.py` | Explicit package inventories, validation, deterministic ZIPs, checksums |
| `dev/install.py` | Install runtime files into a new local skill directory |
| `dev/test_build.py` | Reproducibility, archive rebuild and installation behavior |
| `.github/workflows/ci.yml` | Windows local checks and package build on GitHub |
| `AGENTS.md`, `docs/` | Agent handoff and development/release instructions |

## Edit, test, install

Work on a topic branch. Change runtime scripts and corresponding guides together;
keep bilingual documents aligned. Add regression tests for changed observable behavior.
Use Python packaging tests for packaging changes and the local PowerShell suite for
runtime changes. Review a diff before deploying the result.

From a reviewed checkout, install into a **new** destination reported by your harness:

```powershell
python dev/install.py --destination "$HOME/.agents/skills/pwsh-ssh-bridge"
```

The installer copies only runtime files and refuses an existing destination. To update,
preserve local edits and move the existing installation to a reviewed backup location
outside all discoverable skill roots, then install. Restart/rescan the harness if needed.
Run the environment helper from the installed directory and perform one authenticated
probe only against the user's approved target. Keep the checkout for future changes.

## Live integration tests

Read [Test-Live.ps1](../tests/Test-Live.ps1) before use. The user must authorize the
target and temporary test mutations. Pass an existing reviewed profile; no credentials
are shipped in the repository:

```powershell
pwsh -NoProfile -File ./tests/Test-Live.ps1 `
  -ConfigFile '<private-profile>/ssh_config' -Alias lab -WorkDirectory '<private-scratch>'
```

The suite expects Linux `sh`, `mktemp`, `sha256sum`, `stat`, SFTP and an SSH service
on remote loopback port 22. It creates a unique remote temporary directory, tests
transfer and forwarding, then cleans its listed remote files and tunnel. Local fixture
keys remain in scratch. A failed cleanup must be reported and inspected. CI never runs
this suite automatically. The [verification record](../references/verification.md)
distinguishes historical live results from newly run checks.

## Build and release

`python dev/build.py` writes these files under ignored `dist/`:

- `pwsh-ssh-bridge-X.Y.Z-skill.zip`: installable runtime directory.
- `pwsh-ssh-bridge-X.Y.Z-workspace.zip`: full editable source, tests, docs and build tools.
- `SHA256SUMS`: SHA256 for both ZIPs.
- `manifest.json`: archive hashes and each normalized source file's hash.

Update [VERSION](../VERSION) for a release. Files are UTF-8/LF, ZIP entries have fixed
timestamps and permissions, and data is stored without compression to avoid zlib-version
differences. Packaging tests extract the workspace ZIP and rebuild both packages to
prove source completeness. New top-level source directories must be explicitly added
to the inventories in `dev/build.py`. The validator checks links and obvious private-key
headers; it is not a comprehensive secret scanner. Inspect source/diffs and generated
archives for private identifiers and credentials before publication.

After tests pass, commit the source, tag that exact commit `vX.Y.Z`, and push it. With
GitHub CLI authenticated, an authorized maintainer can publish the already-built assets:

```sh
gh release create vX.Y.Z --verify-tag --title 'vX.Y.Z' --notes-file docs/release-notes.md dist/*
```

Replace the example version with `VERSION`, update the release notes first, and check
remote release assets/checksums after upload. Local build/install never publishes or
changes the machine's SSH configuration.

## Agent handoff

Ask an agent: “Read AGENTS.md and the development guide. Inspect my local tools,
implement the requested change in this checkout, run relevant tests, build both packages,
and install to my chosen skill directory after preserving existing edits.”

The Git repository is the long-term editable workspace. A runtime installation may
direct the agent to clone this repository or download the matching workspace release.
Confirm the source/version before running downloaded code. Other harnesses must verify
their own shell, permissions and skill discovery; the reference tested environment is
Codex on Windows with PowerShell and Windows OpenSSH.
