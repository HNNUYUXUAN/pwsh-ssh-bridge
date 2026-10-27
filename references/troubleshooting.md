# Troubleshoot the failing stage

[简体中文](troubleshooting.zh-CN.md)

Read the last decisive result, identify its stage, and gather one new signal. After two
equivalent failed attempts, change the diagnostic, not the credentials. Preserve an
existing working human terminal while investigating.

| Observation | What it establishes | Next useful check |
|---|---|---|
| Config/key “Access denied” | Local execution identity cannot access that file | Environment identity, ACL, harness permission mechanism |
| Config/key “not found” after access error | Existence may be obscured by access denial | Recheck under authorized identity before recreating files |
| Missing `pwsh`/`ssh` | Local dependency missing | Setup guide's dependency branch |
| TCP timeout/refusal before banner | SSH authentication has not occurred | Listener, mapping, route, firewall/TUN upstream evidence |
| `Connection established` followed by `kex_exchange_identification` | Client saw a connection, but banner/key exchange did not finish | Proxy/TUN logs and synchronized server capture |
| Host-key verification failed/changed | Server identity not verified | Trusted console fingerprint; stop login until resolved |
| `Permission denied (publickey)` | SSH reached authentication | Login account, installed key, ownership/modes and effective server policy |
| Authenticated but command failed | Transport/authentication succeeded | Remote executable, shell syntax, cwd, permission and exit code |
| Helper timeout/exit 255 | Outcome may be unknown | Inspect remote postconditions before deciding to replay |
| JSON contains garbled Unicode | An output boundary may use a different encoding | Check saved script UTF-8 and parent/child output encoding |

## Local evidence

Start with `Test-BridgeEnvironment.ps1` and a reviewed config. Use the actual OpenSSH
executable path it reports. A Windows system SSH client and Git's bundled SSH may use
different agents/config handling; do not switch implicitly.

For one verbose probe, use PowerShell:

```powershell
& '<ssh-executable>' -v -F '<reviewed-config>' -o BatchMode=yes `
  -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -T lab 'id; hostname'
```

Inspect routes only when the network-stage failure calls for it:

```powershell
Find-NetRoute -RemoteIPAddress '<confirmed-target-IP>'
Get-NetAdapter | Where-Object Status -eq 'Up'
```

If a TUN/proxy is involved, inspect only the target-specific connection/log. A TUN can
accept a local TCP connection then time out connecting upstream; SSH may report “closed”
without the Linux SSH server having closed anything. “DIRECT” in a proxy log describes
its selected outbound path, not guaranteed reachability.

Avoid globally disabling networking/proxy settings as a diagnostic shortcut. Any targeted
temporary route test needs a recorded original state, a bounded attempt and reliable
cleanup. First try a known authorized private route; it may avoid such mutation entirely.

## Trusted Linux terminal checks

Send the user a small command block matched to the question. Where sudo is needed,
explain that the password is entered only in their own terminal:

```sh
sudo ss -lntp
sudo /usr/sbin/sshd -T | grep -E '^(port|listenaddress|permitrootlogin|pubkeyauthentication|authorizedkeysfile|maxstartups|allowusers|denyusers|allowgroups|denygroups) '
sudo journalctl -u ssh -u sshd --since '10 minutes ago' --no-pager -n 60
```

`sshd -T` without connection parameters may not reflect conditional `Match` rules.
If authentication is reached and a Match rule matters, inspect its effective settings
with the actual user/source/host using `sshd -T -C ...`. On systems without journald,
check the distribution's authentication log. Missing SSH journal entries do not exclude
packets dropped before SSH authentication. A recent service-start entry alone explains
neither successful nor failed client arrival.

Check a local handshake from Linux when needed:

```sh
ssh-keyscan -T 5 -t ed25519 -p 22 127.0.0.1
```

Use the **observed listener port**, not always 22. This shows whether the server can
respond locally. Collect host identity from the trusted console, not from a scan alone.
The Linux target failing to scan its own public mapping can be a loopback-routing issue;
it is not proof that external users cannot connect.

## Coordinate a packet capture

Use a targeted, bounded capture only when it will distinguish remaining possibilities.
In the Linux terminal (replace the listener port if different):

```sh
sudo timeout 60 tcpdump -nn -i any 'tcp port 22'
```

Ask the user to reply **“capture started”** after `listening on ...`, while leaving the
terminal running. Immediately make one local timestamped connection attempt. Then read
the output and final packet counters. Confirm the capture window covered that attempt.
If tcpdump is absent, request an authorized installation or use existing network tools.
Keep captures to headers for this diagnosis; payload dumping is unnecessary.

| Capture | Interpretation |
|---|---|
| No target packets during confirmed attempt | Investigate upstream route/mapping/filter; account for capture interface/filter/drops |
| SYN arrives, no SYN-ACK | Check listener binding, host firewall and return route |
| SYN arrives, SYN-ACK leaves, ACK absent | TCP remains incomplete; return-path filtering or NAT behavior are candidates |
| Handshake and SSH payload complete | Move to SSH identity/authentication/application diagnostics |

The case behind this skill showed repeated SYNs from the local machine's private
address and repeated SYN-ACK replies from Linux, without a final ACK. Direct private
SSH then succeeded with the same pinned host key. This is consistent with a NAT
reflection/return-path issue; gateway configuration was not captured, so a specific NAT
rule defect was not proved. [Primary explanation of this mechanism](https://www.openbsd.org/faq/pf/rdr.html).

## When the route changes

Obtain the new address from the user's platform or trusted Linux terminal. Verify which
device it belongs to; never infer a neighbor's ownership from adjacent IP numbers.
Test the new endpoint with the existing verified host identity, or provision a new
minimal profile from the same trusted host public key. Stop on mismatch.

Public SSH switches can allocate a new port when toggled. If a provider refresh is
actually needed, explain that effect and obtain the current command afterward. Keep the
old success evidence as history, not a promise that an old route is still available.

## If progress needs the user

State the observed blocker and one next action, with choices where helpful: “Do you have
an already-connected VS Code terminal, another SSH terminal, or a provider console?”
Avoid sending an undifferentiated command dump or repeating the same request for data.
If the host denies an escalation, report that exact restriction and the authorized route
to resolve it. A skill cannot override the harness's permission policy.
