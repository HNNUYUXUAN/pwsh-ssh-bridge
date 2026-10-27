# 使用已核验的连接

[English](operations.md)

使用当前加载的 skill 目录、经过审阅的配置和已核验别名。下文示例在 PowerShell 中运行。
本地工作文件放在可发布源代码目录之外。

## 命令与执行结果

简单读取：

```powershell
& '<skill-root>/scripts/Invoke-Bridge.ps1' -ConfigFile '<profile>/ssh_config' -Alias lab -Command 'hostname; uptime'
```

多行命令、`$`、引号、反引号或中文等内容，优先用 agent 的文件工具写成 UTF-8 `.sh` 文件，
通过 `-ScriptPath` 传递文件名。脚本调用 `ssh -T ... sh -s`，将换行统一为 LF，经标准输入发送后关闭输入。
每次调用都是新的 shell，需要在每份脚本中写明工作目录、环境变量和失败处理方式。

```sh
set -eu
cd /srv/project
git status --short
```

标准输入用于传输脚本；脚本中的命令如果继续读取标准输入，可能吃掉后续脚本行。
应明确重定向其输入，或上传脚本并设计独立的数据输入方式。
需要人工确认或 sudo 密码的命令由用户在可信交互终端完成，或使用已经获准的非交互 sudo 规则；
不把密码写入脚本文本。

默认远端 shell 为 POSIX `sh`。需要 Bash 语法时，在提交脚本中明确调用 Bash，
或上传文件后执行 `bash /path/file`。脚本不会为所有任务自动添加 `set -e`；按任务需要指定错误策略。

执行结果字段：

| 字段 | 含义 |
|---|---|
| `schemaVersion=1` | 此 helper 的 JSON 结果版本 |
| `outcome=completed` | 进程返回 0，仍需检查预期输出与操作后置条件 |
| `outcome=failed` | 除 255 外的非零结果，检查错误输出和远端状态 |
| `outcome=unknown` | 超时或退出 255；远端操作可能已经执行 |
| `outcome=local_error` | 本地参数校验或运行错误，检查 message |
| `transportExitCode` | OpenSSH/scp 的退出码；SSH 通常传回远端 shell 的退出码 |
| `timedOut` | 本地执行期限到达，helper 终止其本地子进程树 |
| `stdout`、`stderr` | 分开的 UTF-8 输出，各自受 MaxOutputChars 限制 |
| `stdoutChars`、`stderrChars` | 截断前观测到的解码字符总量 |
| `outputTruncated` | 一部分输出被丢弃，但持续读取避免管道阻塞 |
| `automaticRetry=false` | helper 不自动重放操作 |

默认命令期限 60 秒，每个输出流最多保留 65,536 字符；按需设置 `-TimeoutSeconds` 和 `-MaxOutputChars`。
Helper 超时退出 124，否则传回子进程退出码；本地 helper 错误为 2。
远端程序本身也可能返回 124 或 255，因此要结合 JSON 和上下文判断。
PowerShell 参数绑定错误或运行时缺失可能发生在 JSON 生成之前。
日志截断不构成重跑有副作用命令的理由。

终止本地 SSH 不能证明远端进程已经停止。结果不确定时，另外发起只读命令，
检查该任务的文件、PID、作业 ID 或服务状态。重新连通不等于可以自动重放前一条操作。

## 文件：暂存、复制、核验、应用

Helper 使用 OpenSSH 9+ 默认的 SFTP 协议复制**单个文件**，与 SSH 使用同一套 OpenSSH 程序和主机身份配置。
远端路径必须是绝对 POSIX 文件路径；拒绝通配符、符号链接和目录目标。
复制前的检查并不是事务或并发锁。

复制可能覆盖目标。`-AllowDestinationOverwrite` 显式表明该行为；agent 仍须从用户任务确认目标写入授权，
不能因为存在这个参数就认为获得了授权。推荐使用唯一临时文件：

```powershell
& '<skill-root>/scripts/Copy-BridgeFile.ps1' -Direction Upload `
  -ConfigFile '<profile>/ssh_config' -Alias lab `
  -LocalPath '<本地工作目录>/config.new' -RemotePath '/tmp/task-unique/config.new' `
  -AllowDestinationOverwrite
```

先用限定范围的远端命令创建临时目录。
下载时先创建本机父目录，使用 `-Direction Download`，明确本机目标文件名。
两端路径可以有空格；目标应为文件名。批量递归传输需要另行选择适合任务的流程。

修改文件时：获取所需文件、检查并在本地编辑、审阅 diff、上传唯一临时路径、核验 SHA256，
然后在任务授权范围内应用。替换共享文件前，重新检查原文件是否已改变，并保留所需备份、属主与权限。
项目已有发布机制时使用项目机制。普通复制不保证全部元数据或原子发布。
复制失败会返回 `destinationMayBePartial=true`；先检查或删除明确属于本任务的临时文件，再决定是否重试。

## 真正的本地端口转发

本机应用需要访问 Linux 能访问的服务时，可建立隧道。普通远端命令执行不需要在本机监听端口。

```powershell
& '<skill-root>/scripts/Open-BridgeTunnel.ps1' `
  -ConfigFile '<profile>/ssh_config' -Alias lab `
  -LocalPort 18080 -RemoteHost 127.0.0.1 -RemotePort 8080
```

脚本以前台方式运行 SSH `-N -L`，设置 `ExitOnForwardFailure=yes`，并在本机绑定 `127.0.0.1`。
远端目的地址由 **SSH 服务端**理解：示例中的远端 `127.0.0.1:8080` 是 Linux 上的服务，
本机 `127.0.0.1:18080` 是 agent 所在电脑的访问入口。

输出“Starting”不等于隧道已就绪。检查进程仍在运行、本地端口属于预期 SSH 进程，
并通过它验证实际服务响应。监听成功也可能遇到远端服务不可用。
保持 harness 工具会话或人工终端运行；用 Ctrl+C 停止并验证端口已关闭。
如果 harness 后台启动 Windows 进程，使用隐藏窗口选项，记录该进程 PID，仅终止本任务拥有的进程。
只有用户要求时才配置开机启动、监控或常驻服务。

## 长任务和重新连接

`ServerAliveInterval` 用来发现连接中断，不会自动重连、重启 agent 或保存 shell 状态。
长任务可使用远端已经存在、且任务授权允许的作业机制，例如具名 tmux 会话或项目作业运行器。
记录作业身份与检查方式。先确认 tmux 是否存在，不自动安装或开启持久化服务。

设备重启后重新执行认证探测。地址变化属于路由变化，主机密钥变化属于需要可信核验的身份事件。
不能为了消除警告就删除 known-hosts 记录。

## 跳板机和只能主动出站的目标

首条实测路径是直接 SSH。用户已有 `ProxyJump` 别名时，可以审阅并复用，分别检查跳板机凭据与主机密钥。
常规由本地客户端管理的 ProxyJump 不需要向远端转发 ssh-agent。

没有获准的入站路径时，用易懂语言说明选项：复用既有跳板机、请服务商提供映射，或与网络所有者
设计获准的主动出站反向隧道/组网路径。配置前明确中继所有者、暴露的地址和端口、双方身份、生命周期与清理方式。
这些拓扑需单独测试；附带实机测试覆盖直接 SSH 和本地 `-L`。
