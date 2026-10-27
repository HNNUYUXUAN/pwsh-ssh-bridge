# Research and attribution

[简体中文](research.zh-CN.md)

Research reviewed on 2026-10-26–27. Discovery used Tencent Yuanbao Search first, with
GitHub's connected tools for repository content and metadata. Official pages were fetched
for protocol/platform claims. Community material informed questions and hypotheses.

## Open-source skill/tool comparisons

| Source snapshot | Useful design evidence | Application here |
|---|---|---|
| [ssh-remote-dev, 58e1cf4](https://github.com/rogue-shadowdancer/codex-skill-ssh-remote-dev/blob/58e1cf4bea23631997eee5fed968784b16824c2d/SKILL.md) | Windows-aware remote inspection and local staging/edit/upload workflow; explicit sandbox identity concerns | Include staged edits, effective-identity checks and a supported permission path |
| [ssh-skill, c6c8a18](https://github.com/kyaring/ssh-skill/blob/c6c8a184a7d8c8b217860a015f5860418647d8ea/SKILL.md) | Structured result contract; bounded outputs; unknown outcomes and avoiding command replay | Explicit JSON result fields, bounded stream capture and conservative timeout semantics |
| [AgentSSH, ed0780a](https://github.com/trtyr/AgentSSH/blob/ed0780afc99c2027e7ab8b84a0e1dc230819db0f/SKILL.md) | Clear separation of one-shot execution, interactive/session operations and forwarding | Distinguish a successful one-shot command from persistent jobs and actual port tunnels |

These are independent external implementations, not tested dependencies of this package.
The reviewed repository metadata reported LGPL-2.1 for ssh-remote-dev and MIT for AgentSSH;
the GitHub metadata for ssh-skill did not identify a license. No external source code or
skill text is bundled here. Links identify the researched snapshots; new releases may differ.

This package uses its own PowerShell/.NET runner and the operating system's OpenSSH. The
initial setup flow is grounded in the case evidence: check the user's two endpoints,
bootstrap through existing trusted access, retain verified identity while changing route,
and revalidate under the harness's real execution identity.

## Primary documentation used

- [Codex skills](https://developers.openai.com/codex/skills): skill discovery, SKILL.md,
  optional resources and the current user skill directory. Full Markdown was fetched
  from the official `.md` endpoint after the web reader could not render that format.
- [Codex Windows](https://developers.openai.com/codex/windows): local shell/filesystem/network
  permissions and execution identity matter independently of remote SSH authorization.
- [OpenSSH ssh_config](https://man.openbsd.org/ssh_config): first-obtained configuration
  values, HostKeyAlias, strict host checks, batch behavior, keepalives and forwarding controls.
- [OpenSSH ssh-keyscan](https://man.openbsd.org/ssh-keyscan): collecting a key does not
  authenticate its source; verify it through a trusted channel.
- [OpenSSH scp](https://man.openbsd.org/scp): modern scp uses SFTP; paths and failure status
  still require deliberate handling.
- [Microsoft OpenSSH key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement):
  key/agent workflow and Windows credential handling.
- [ProcessStartInfo.ArgumentList](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.argumentlist):
  pass discrete native arguments rather than assembling a shell command string.
- [OpenBSD PF redirection and reflection](https://www.openbsd.org/faq/pf/rdr.html):
  explains how a same-network reply can bypass the translating gateway and prevent a handshake.

## Forum experience and evidentiary limits

Yuanbao surfaced the Server Fault discussion
[“Loopback to forwarded Public IP address from local network – Hairpin NAT”](https://serverfault.com/questions/73237/loopback-to-forwarded-public-ip-address-from-local-network-hairpin-nat)
and [a related answer](https://serverfault.com/a/729252). Search excerpts describe
the same-network source/destination translation issue. Direct page retrieval was unavailable
during this review, so no forum text or firewall rule is reproduced and the diagnosis rests
on the local case plus the accessible primary OpenBSD documentation.

The practical takeaway is to compare client-visible state, proxy upstream logs and server
packet evidence. It is not a universal instruction to add NAT rules. Provider-managed
network changes need the provider/network owner's context and authorization.

## Independent implementation and validation

This repository's code, setup procedure and bilingual documentation were written for this
workflow. Local and live tests verify observable behavior; the exact coverage and remaining
boundaries are listed in [verification](verification.md). The external projects' assertions
are design references, not compatibility claims for this package.
