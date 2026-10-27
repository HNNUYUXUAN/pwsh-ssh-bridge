# A real connection, with identifying details replaced

[简体中文](case-study.zh-CN.md)

This case was observed in October 2026. Addresses, account labels, hostnames, local
paths and key material in this document are illustrative. Packet relationships and
the order of the decisive observations are preserved. The original session supplied
the evidence; the published package contains this narrative rather than raw credentials
or unsanitized logs.

## Goal and environment

A user ran Codex on a Windows cloud workstation and wanted it to operate a Linux cloud
workstation. Installing and signing into the agent harness on Linux was inconvenient.
The user could open a trusted Linux terminal. Windows already had PowerShell 7 and
OpenSSH; a TUN/proxy application was also active.

Illustrative topology:

```text
Windows local agent 10.23.7.10
    → public SSH mapping 192.0.2.40:22022
    → Linux sshd 10.23.7.11:22
```

The cloud panel enabled SSH and showed an unrestricted IP allowlist. The session's
chosen account was root; account choice remained an explicit part of the user's task.

## Establishing credentials and identity

A dedicated Ed25519 login key was created locally, with the private file restricted
to its creating Windows account. Only the public key was sent to the Linux console.
The first install attempt ran under an ordinary console account and failed when
writing the target account's home. Running the targeted installation through authorized
sudo succeeded while preserving existing authorized keys.

The Linux console provided the server's Ed25519 host public key and SHA256 fingerprint.
They were matched locally and pinned in a separate known-hosts file. This let later
route changes retain the same identity check.

## Evidence that changed the diagnosis

| Observation | Supported conclusion |
|---|---|
| Public connection logged “Connection established,” then closed before SSH banner | The client-visible connection did not complete SSH negotiation |
| Linux listened on 22 and responded to a local keyscan | The local SSH service could negotiate |
| Journal showed service startup but no matching login attempt | No authentication-stage event was visible in that log |
| TUN log reported a DIRECT upstream timeout | Local acceptance and upstream connectivity were different stages |
| Public SSH refresh allocated a different port, with the same failure | Refreshing that entry point did not resolve the observed path |
| Coordinated capture saw SYN and SYN-ACK, but no final ACK | The request reached Linux; TCP did not finish |
| Private-IP SSH succeeded with the pinned host key | The intended machine was reachable through that private route |

The decisive capture, with values replaced:

```text
In:  10.23.7.10:51000 → 10.23.7.11:22  SYN
Out: 10.23.7.11:22 → 10.23.7.10:51000  SYN-ACK
In:  10.23.7.10:51000 → 10.23.7.11:22  SYN (retry)
Out: 10.23.7.11:22 → 10.23.7.10:51000  SYN-ACK (retry)
```

The capture contained the local workstation's private source address. Together with
successful private-IP access, this was consistent with a public-mapping reflection or
return-path problem. The gateway's NAT configuration and both directions at every hop
were not available, so a particular missing SNAT rule was not established as fact.

## Working connection and later reuse

The working path became:

```text
Codex → local PowerShell → SSH 10.23.7.11:22 → Linux command
```

Host-key validation, key authentication, hostname/account checks, and remote command
execution passed. A reusable PowerShell entry point kept the private route as the
working default and stored the public endpoint as a separate known option.
Later reconnection attempts after device startup succeeded through the private route.
One later harness session could not read the existing key/config under its sandbox
identity; the supported permission flow allowed the existing credentials to be reused.

## What generalizes

- Ask which remote terminal is available and verify its account before installing a key.
- Separate login-key setup, server identity, network reachability and operation results.
- Inspect the actual route and proxy upstream when the apparent TCP state is confusing.
- Coordinate the user's capture and the agent's attempt, including timing.
- Test a confirmed private address with the same verified host identity when appropriate.
- Save a private reconnect record, then probe again after restart.

## What needs new evidence elsewhere

A private network may not exist between a different user's local computer and target.
Public mappings, bastions, overlays and outbound reverse tunnels need their own routing
and authorization checks. An arbitrary chat surface may not expose local tools. Root
access, Windows paths, cloud product behavior and persistent background execution should
all be established from the current environment rather than copied from this case.
