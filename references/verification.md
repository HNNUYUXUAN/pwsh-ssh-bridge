# Verification record

[简体中文](verification.zh-CN.md)

Validation date: **2026-10-27**. This is a single-environment test record, not a
cross-platform certification. The agent executed these helpers from a local Codex
session on Windows against the user's already-authorized Linux device.

## Environment

| Component | Observed version / condition |
|---|---|
| Local harness | Codex desktop session with command tools and supported permission escalation |
| Windows | Build 10.0.20348 |
| PowerShell | 7.6.7 |
| Local OpenSSH | OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2 |
| Remote | Linux, Ubuntu 22.04.5 LTS; OpenSSH 8.9p1 family |
| Route | Confirmed private IPv4 address, with an independently verified Ed25519 host key |
| Credentials | Existing approved login key referenced in place |

The actual addresses, usernames, key data and private configuration paths are omitted
from this public record. The [case study](case-study.md) uses illustrative replacements.

## Automated checks

`tests/Test-Local.ps1` passed **23 checks**, including 8 script syntax checks and 15
behavioral checks: stdin/Unicode/metacharacters, independent stderr and exit status,
bounded stdout/stderr draining, timeout and exit-255 semantics, key generation and ACL,
key/profile overwrite refusal, matching and mismatching fingerprints, generated config
resolution by OpenSSH, LF console script output, alias option rejection, missing script
handling, and wildcard transfer rejection.

`tests/Test-Live.ps1` passed **13 checks** using a newly generated profile from this
skill and the existing trusted credentials:

1. Authenticated probe.
2. Unicode, CRLF script input, literal quoting and remote exit status.
3. Isolated remote temporary directory.
4. Binary upload with spaces in paths.
5. Binary download and SHA256 roundtrip equality.
6. Timeout with unknown outcome and no automatic replay.
7. Disposable bootstrap fixture key generation.
8. Wrong host key blocks live command execution.
9. Console installation script generation.
10. Console script upload.
11. Idempotent public-key installation and permissions in an isolated synthetic-account fixture.
12. Local loopback forwarding returns the remote SSH service banner.
13. An occupied local tunnel port fails explicitly.

Tests used unique temporary directories. The bootstrap fixture redirected account lookup
to its temporary home; the real account's authorized_keys was untouched. Test files and
tunnel processes were cleaned up. A final bundle audit validates links, metadata,
private-data exclusions and archive content.

## Findings addressed during implementation

- A sandbox identity could generate a key but could not set the intended private ACL.
  The helper reported failure; the authorized local-user context passed the ACL check.
- Redirected child PowerShell JSON inherited a local code page and corrupted Unicode.
  The module now sets UTF-8 output explicitly; the live Unicode test passed afterward.
- A second Windows OpenSSH forward did not terminate as expected for an already occupied
  local port. The helper now performs an exclusive loopback-port availability check,
  retains SSH's forwarding-failure option, and requires service verification. The
  precheck is not an atomic reservation; callers must still inspect the actual listener.

## Boundaries

PowerShell 7.2 is the declared runtime minimum; the executed version was 7.6.7. Encrypted
keys with ssh-agent, first-time OS package installation, arbitrary VS Code configurations,
IPv6 forwarding, jump hosts, reverse tunnels, alternative Linux distributions, other
harnesses and long-running daemon lifecycle were not exercised by this suite.

The novice setup instructions and bilingual guidance were reviewed against the case
and scripted error branches. They have not been evaluated as a user study or an independent
fresh-agent run. The scripts can guide and inspect an environment; they cannot guarantee
that every model will make correct operational decisions.

## Reproduce

Run from a trusted PowerShell 7 terminal, using private scratch space:

```powershell
pwsh -NoProfile -File ./tests/Test-Local.ps1 -WorkDirectory '<private-scratch>'
pwsh -NoProfile -File ./tests/Test-Live.ps1 `
  -ConfigFile '<reviewed-profile>/ssh_config' -Alias lab -WorkDirectory '<private-scratch>'
```

The live test expects the target's SSH service at remote loopback port 22 for its tunnel
check and Linux `sha256sum`, `stat`, `mktemp` and `sh` for fixtures. Review the test before
running it on a different device. It reads the approved profile and creates/removes only
its unique test files. Local scratch directories retain disposable keys and diagnostics;
keep them private and remove them when no longer needed.

## Open-source workspace packaging

The publication preparation on 2026-10-27 reran all 23 local PowerShell checks.
Four Python packaging tests passed: reproducible archives with the expected inventories,
rebuilding the extracted workspace to identical packages, exact runtime installation
with preservation of an existing destination, and rejection of broken package links.
The official skill validator and a local privacy-marker audit also passed.

This publication pass did not rerun Linux integration tests. The 13 live results above
are the earlier implementation validation. GitHub Actions executes the local checks
and build on a separate Windows runner; consult the commit's Actions result for that
runner's actual outcome.
