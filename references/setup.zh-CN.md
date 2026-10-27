# 首次连接：双端配置

[English](setup.md)

从第一个未完成的检查点开始。每条命令都明确属于哪台设备、哪个终端；发送前替换示例值。
已经完成的步骤，在没有新证据推翻时继续复用。

## 1. 确认 agent 实际具备的能力

只询问缺失信息：目标连接命令与账户、现有远端入口、本地 agent 是否能执行终端命令。
复用已获准读取的相关记忆、对话证据、SSH 别名和用户终端偏好。
记忆中的地址与指纹仍须验证；记忆本身不等于凭据。

没有命令工具时，用易懂的话说明：“当前聊天可以准备命令；要自动执行，请在能使用本机终端的
本地 agent 会话中打开此任务。”随后仍可提供人工执行步骤。

明确实际本地 shell：Git Bash 使用 `/c/...` 路径，PowerShell 使用 Windows 路径。
Git Bash 中可通过 `pwsh -NoProfile -File 'C:/path/to/script.ps1' ...` 运行脚本，保留用户的默认终端。
若工具声明的 shell 与实际执行结果不符，先用最小版本/身份命令确认，避免不断叠加 shell 包装。

### 本机 Windows 依赖

尚不确定是否装有 PowerShell 7 时，在普通 Windows PowerShell 终端检查：

```powershell
$PSVersionTable.PSVersion
Get-Command pwsh, ssh, ssh-keygen, scp -ErrorAction SilentlyContinue | Select-Object Name, Source
```

成功标志：存在 `pwsh`，其版本至少为 7.2，并有 OpenSSH。
缺少 PowerShell 7 时，按用户允许的软件渠道安装。可用 WinGet 时，可由用户执行
`winget install --id Microsoft.PowerShell --exact`，随后打开新终端。
受管理设备采用管理员提供的软件包。

缺少 Windows OpenSSH 时，在已获授权的管理员 Windows PowerShell 中检查并安装**客户端**：

```powershell
Get-WindowsCapability -Online -Name 'OpenSSH.Client*'
Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0'
```

这一步安装本机客户端，Linux 的 SSH 服务是另一端的组件。
接着在 PowerShell 7 运行 `scripts/Test-BridgeEnvironment.ps1`。
JSON 会报告实际 Windows 执行账户、程序路径和 SSH 版本。
`networkTested=false` 表示尚未测试网络，不能将它理解为远端已经连通。

### 凭据与沙箱账户

Harness 可能以沙箱账户执行命令，而非用户交互登录的 Windows 账户。
读取既有 `.ssh` 配置或密钥时的“拒绝访问”属于本地权限问题，即使后续还伴随“找不到文件”。
通过 harness 支持的权限申请机制申请读取既有配置/密钥与连接目标网络。
保持密钥 ACL，避免把密钥复制到仓库或输出目录来规避被拒绝的权限边界。

陌生 SSH 配置在交给工具前应检查 `ProxyCommand`、`Match exec` 和包含文件；它们可能执行本地命令。
已经审阅的配置可以复用。

## 2. 找到可信的远端终端

根据用户已有入口提供具体指引：

| 已有入口 | 操作 |
|---|---|
| VS Code 已通过 Remote-SSH 连接 | 在该远端窗口选择“终端 → 新建终端”，运行 `hostname; id; pwd` 确认是 Linux |
| 普通 SSH 客户端已登录 | 保持这个终端打开，执行相同身份检查 |
| 云网页控制台或 Linux 图形桌面 | 打开其中的终端，执行身份检查 |
| 没有已认证终端或可信服务商入口 | 先使用服务商恢复控制台或请管理员提供初始访问 |

VS Code 的一个终端可能仍在本机执行，必须检查主机名与 `id` 输出。
`PS C:\...>` 一类提示符说明当前是本机 Windows。
VS Code 使用的 `Host` 别名可能包含跳板机、ssh-agent 或另一把密钥；检查并复用相关配置，
不要直接假定公网 IP 可以直连。

密码只在用户自己的终端输入，不要求发送到聊天。
没有初始可信入口时，说明具体需要哪项服务商操作；本地脚本不能凭空获得远端授权。

### Linux 环境和权限

在可信 Linux 终端执行：

```sh
hostname
id
command -v sh
command -v getent
ss -lnt
```

控制台脚本需要 Linux 的 `getent`、`awk`、`cut` 和常规文件工具。
精简发行版缺少工具时，说明缺项，按该系统准备经过审阅的人工流程；不能猜测用户家目录或强行使用 root。

如果 VS Code 或另一个 SSH 终端已经连接，SSH 服务已经存在。
否则检查 `sshd` 和本发行版的服务管理器。
对于获准安装 SSH 服务的 Ubuntu/Debian，可指导用户执行：

```sh
sudo apt-get update
sudo apt-get install openssh-server
sudo systemctl enable --now ssh
```

随后重新检查监听端口。云平台公网端口可以与 Linux 监听端口不同，应先理解映射关系。
其他发行版使用对应的软件包和服务名。

明确目标登录账户。若控制台账户与目标账户不同，需要切换到目标账户的会话或使用已获授权的 sudo。
例如，普通账户不能直接写入 `/root/.ssh/authorized_keys`。

## 3. 在本机复用或创建登录密钥

优先复用已经获准用于该主机的合适密钥。需要新建时，向用户解释两种方式：

- **口令保护 + ssh-agent**：用户在自己的本机终端解锁；后续批处理必须能访问同一 agent 上下文。
- **专用无人值守密钥**：不设口令，由本机账户和密钥 ACL 保护；用于用户明确选择的无人值守场景。

在仓库与交付目录以外创建私有凭据目录。本机 PowerShell 示例：

```powershell
$credentialDir = Join-Path $HOME '.ssh/agent-bridge-lab'
New-Item -ItemType Directory -Path $credentialDir -Force | Out-Null
& '<skill-root>/scripts/New-BridgeKey.ps1' -Path (Join-Path $credentialDir 'login_ed25519')
```

此命令会交互询问口令，应该在用户自己的可交互终端运行。
用户选择无人值守方式时，添加 `-Unattended`；脚本输出 JSON，并将新私钥权限限制到创建账户。
脚本拒绝覆盖已有密钥。若生成后设置权限失败，需检查已创建文件再继续，不能报告为准备完成。

使用 Windows 上的加密密钥时，先检查 `Get-Service ssh-agent`。
若用户选择启用已停止/禁用的服务，在获准的管理员终端配置并启动，再由用户交互执行
`ssh-add '<私钥路径>'`。Agent 的可见性与账户有关，必须通过 harness 的真实执行上下文验证。

## 4. 准备并安装登录公钥

在本机按选定的远端账户生成脚本：

```powershell
& '<skill-root>/scripts/New-ConsoleSetup.ps1' `
  -PublicKeyFile '<私钥路径>.pub' -TargetUser operator `
  -OutputFile '<私有工作目录>/install-public-key.sh'
```

读取生成结果。脚本会查询目标账户的真实家目录、检查权限、保留已有公钥及匹配密钥上的限制，
拒绝符号链接形式的 SSH 路径，成功时打印 `PUBLIC_KEY_INSTALLED`。

能保存远端文件的用户，可用 VS Code 远端编辑器或既有传输方式将文件保存到 Linux，
然后以目标账户执行 `sh /path/install-public-key.sh`；需要且获准时执行 `sudo sh /path/install-public-key.sh`。

只有粘贴入口时，将**完整生成内容**放进单引号 heredoc：

```sh
sh <<'BRIDGE_SETUP'
# 展示给用户之前，将这一行替换为完整的生成脚本。
BRIDGE_SETUP
```

为另一个账户安装且已获 sudo 权限时，将开头改为 `sudo sh`。
不能把上面的占位行作为实际操作指令发送给用户。
Sudo 密码留在用户终端。如果粘贴带入 `^[[200~` 或尾部 `~`，清空命令行，再粘贴干净的代码块。

成功标志：`PUBLIC_KEY_INSTALLED user=<所选账户>`。
出现错误时不能因为后续诊断命令成功，就宣称安装已完成。

## 5. 获取并固定服务器身份

在**可信 Linux 终端**读取：

```sh
cat /etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

这些是服务器公开身份信息，与第 4 步安装的登录公钥用途不同。
若读取公钥文件需要权限才加 sudo；不读取对应私钥。
服务器没有 Ed25519 主机密钥时，检查支持的算法并创建经过审阅的手工 OpenSSH 配置；
本版自动配置脚本只验证 Ed25519。

将 `ssh-ed25519 ...` 这一行保存为本机文本文件，并将终端显示的 `SHA256:...` 指纹单独传给配置脚本。
若使用 `ssh-keyscan` 获取网络公钥，仍要先与可信终端指纹核对。
[OpenSSH 文档说明 keyscan 本身不能认证服务器身份](https://man.openbsd.org/ssh-keyscan)。

```powershell
& '<skill-root>/scripts/New-BridgeProfile.ps1' `
  -Directory '<私有目录>/profile' -Alias lab `
  -HostName '192.0.2.40' -Port 22022 -UserName operator `
  -IdentityFile '<私钥路径>' `
  -HostPublicKeyFile '<私有工作目录>/host-ed25519.pub' `
  -ExpectedFingerprint 'SHA256:<实际指纹>'
```

替换所有示例值。脚本创建独立配置和 known-hosts 文件，固定主机身份别名，
拒绝指纹不符或覆盖已有配置目录，并引用原位置的密钥。
创建配置还不能证明网络已连通。

## 6. 验证登录并选定有效路径

```powershell
& '<skill-root>/scripts/Invoke-Bridge.ps1' `
  -ConfigFile '<私有目录>/profile/ssh_config' -Alias lab -Probe
```

成功条件：`outcome=completed`、退出码为 0、包含 `bridge_probe=ok`，并且账户和主机名符合用户预期。
端口可达、平台界面显示开启或公钥已安装，都不足以单独证明登录成功。

公网映射失败时进入[故障诊断](troubleshooting.zh-CN.md)。通过用户确认或可信终端取得目标内网地址，
仅测试已确认的路径。为同一设备切换地址或端口时，保留已核验的主机密钥和 HostKeyAlias。
探测成功后再保存路径变更。使用跳板机需要用户授权，并分别核验跳板机和最终主机身份。

## 7. 保存重连所需信息

在私有位置记录：别名、配置路径、当前有效网络路径、用户名、已验证指纹、观测到的主机名、
最后成功时间和授权范围。有获准使用的 harness 记忆能力时可采用，否则使用用户指定的本地记录。
记录带 `-Probe` 的重连命令，保留密码和密钥内容在凭据存储中。

设备重启后重新探测。地址或端口改变时，确认新入口并保持主机身份校验。
新路径验证成功前，保留已有可信控制台连接。
