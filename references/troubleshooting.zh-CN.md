# 按失败阶段排查

[English](troubleshooting.md)

读取最近一次有判断价值的结果，确定失败阶段，然后获取一个新证据。
两次等价尝试失败后，应改变诊断方法。排查时保留已经可用的人工终端。

| 现象 | 能确认什么 | 下一项有效检查 |
|---|---|---|
| 配置/密钥“拒绝访问” | 当前本地执行账户无权读取该文件 | 环境账户、ACL、harness 权限机制 |
| 拒绝访问后又出现“找不到” | 文件是否存在可能被权限错误遮蔽 | 先在获准账户下检查，再决定是否重建 |
| 缺少 pwsh/ssh | 本地依赖缺失 | 配置指南中的依赖分支 |
| Banner 前 TCP 超时/拒绝 | 尚未进入 SSH 身份验证 | 监听、映射、路由、防火墙/TUN 上游证据 |
| Connection established 后出现 kex_exchange_identification | 客户端看到连接，但未完成 SSH 握手 | 代理/TUN 日志和同步服务端抓包 |
| 主机密钥校验失败或变化 | 服务器身份未核验通过 | 可信控制台指纹，解决前停止登录 |
| Permission denied (publickey) | 已经到达 SSH 认证阶段 | 登录账户、公钥、属主权限、有效服务端策略 |
| 已认证但命令失败 | 传输与身份认证成功 | 远端命令、shell 语法、工作目录、权限与退出码 |
| Helper 超时或退出 255 | 操作结果可能不确定 | 先检查远端后置条件再决定是否重放 |
| JSON 中文乱码 | 某个输出边界可能使用了不同编码 | 检查脚本 UTF-8 和父子进程输出编码 |

## 本机证据

先运行 `Test-BridgeEnvironment.ps1`，使用已审阅配置和报告的真实 SSH 程序路径。
Windows 系统 OpenSSH 与 Git 附带的 SSH 可能使用不同 agent 或配置方式，应明确选择。

需要详细日志时，在 PowerShell 中做一次探测：

```powershell
& '<ssh-executable>' -v -F '<已审阅配置>' -o BatchMode=yes `
  -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -T lab 'id; hostname'
```

网络阶段失败且需要路由证据时：

```powershell
Find-NetRoute -RemoteIPAddress '<已确认目标IP>'
Get-NetAdapter | Where-Object Status -eq 'Up'
```

涉及 TUN/代理时，只检查目标相关连接或日志。TUN 可能先接受本地 TCP，再在上游连接超时；
SSH 随后显示“关闭”，不能据此认定 Linux SSH 服务主动断开。
代理日志中的 DIRECT 表示它选定的出站路径，不保证已经连通。

优先测试已知获准的内网路径。不要把全局关闭网络/代理作为快捷诊断。
确需临时定向路由测试时，先记录原始状态，限定测试次数，并确保清理。

## 可信 Linux 终端检查

按要回答的问题给用户一小段命令；需要 sudo 时说明密码只在用户自己的终端输入：

```sh
sudo ss -lntp
sudo /usr/sbin/sshd -T | grep -E '^(port|listenaddress|permitrootlogin|pubkeyauthentication|authorizedkeysfile|maxstartups|allowusers|denyusers|allowgroups|denygroups) '
sudo journalctl -u ssh -u sshd --since '10 minutes ago' --no-pager -n 60
```

未带连接参数的 `sshd -T` 可能无法反映特定 `Match` 条件。
已进入认证且确有 Match 规则影响时，以真实用户/来源/主机信息使用 `sshd -T -C ...` 检查有效配置。
没有 journald 的系统查看相应认证日志。没有 SSH 日志不等于没有数据包到达，
只有服务启动记录也无法单独解释客户端到达情况。

需要检查 Linux 内部握手时：

```sh
ssh-keyscan -T 5 -t ed25519 -p 22 127.0.0.1
```

端口应替换为**实际监听端口**。此检查只能说明本机服务是否回应；身份核验仍依赖可信控制台。
Linux 无法扫描自己的公网映射可能属于回环路径问题，不能证明真正的外网客户端也一定失败。

## 协调抓包

只有在抓包能区分剩余可能性时才执行定向、限时抓包。
Linux 终端中运行，按需要替换实际监听端口：

```sh
sudo timeout 60 tcpdump -nn -i any 'tcp port 22'
```

请用户看到 `listening on ...` 后立即回复“已开始抓包”，保持终端运行；
agent 随即做一次带时间戳的本机连接尝试，再检查输出与最终计数，确认抓包时间覆盖了该尝试。
缺少 tcpdump 时，申请获准安装或使用现有网络工具。此诊断只需报文头，无需抓取载荷内容。

| 抓包结果 | 解读 |
|---|---|
| 确认的尝试窗口内没有目标报文 | 检查上游路由/映射/过滤，同时考虑接口、过滤条件和丢包计数 |
| SYN 到达，没有 SYN-ACK | 检查监听绑定、主机防火墙和回程路由 |
| SYN 到达，SYN-ACK 发出，没有 ACK | TCP 握手未完成，回程过滤或 NAT 行为是候选解释 |
| 握手与 SSH 数据均完成 | 转入主机身份、用户认证或应用层诊断 |

本 skill 的案例中，服务端看到来自本机内网地址的重复 SYN，并发出重复 SYN-ACK，但没有最终 ACK。
随后使用同一固定主机密钥的内网直连成功。现象符合 NAT 回环/回程问题，但没有获得网关配置，
因此不能证明具体哪一条 NAT 规则有缺陷。
机制可参阅[OpenBSD 原始文档](https://www.openbsd.org/faq/pf/rdr.html)。

## 地址变化时

从用户平台或可信 Linux 终端取得新地址，确认属于目标设备；不能根据相邻 IP 就推断设备所有权。
使用已有核验主机身份测试新入口，或用相同可信主机公钥生成新的最小配置。身份不符时停止。

平台 SSH 开关重开后可能分配新端口。确需刷新平台入口时，先解释这一影响，再获取新命令。
既往成功证据保留为历史记录，当前可用性仍须探测。

## 需要用户协助时

说明已观察到的阻碍和一个下一步操作，需要时提供选项：“你有已连接的 VS Code 终端、其他 SSH 终端，
还是服务商控制台？”避免无差别命令堆叠或重复索取已提供的信息。
宿主拒绝权限升级时，明确报告限制及获准解决方式；skill 不能覆盖 harness 的权限策略。
