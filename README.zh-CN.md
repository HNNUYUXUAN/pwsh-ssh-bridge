# PowerShell SSH Bridge

[English](README.md)

让本地运行的 agent 通过 PowerShell 和 OpenSSH 操作 Linux 的 Agent Skill。
从环境未配置的状态开始，检查依赖、协助双端配置、核验服务器身份、排查网络路径，
再执行命令、传输文件或建立本地端口转发。

```text
本机 Codex 会话 → PowerShell 7 → OpenSSH → Linux sshd → 已获授权的命令
```

远端需要 SSH 服务和 shell；agent harness 及其登录留在本机。
用户可用已经连接的 VS Code SSH 终端、普通 SSH 终端或云服务商可信控制台完成首次配置。

## 支持与验证范围

验证目标为 **Windows 上的 Codex → PowerShell 7 → Windows OpenSSH → Linux**。
指引按实际能力编写，便于其他 harness 适配；新增 harness 或平台需分别验证终端工具、
权限机制、参数传递和运行行为。具体实测状态见[验证记录](references/verification.zh-CN.md)。

这里的“Bridge”表示本地 agent 调用 SSH。可选转发脚本会建立真正的 SSH `-L` 隧道。
SSH 仍需要用户有权使用且能够到达目标的网络路径，例如内网、公网映射或另行配置的接入路径。

## 安装到 Codex

从 [Releases](https://github.com/HNNUYUXUAN/pwsh-ssh-bridge/releases) 下载 `*-skill.zip`
和 `SHA256SUMS`。用 `Get-FileHash -Algorithm SHA256` 对照 ZIP 校验值，解压到新目录并
检查内容。包内的 `pwsh-ssh-bridge` 文件夹可复制到宿主报告的用户技能目录，例如
`$HOME/.agents/skills`。替换前保留已有安装与本地修改，并避免出现同名重复技能。

从已审查的源码目录安装时，使用 Python 3.10+：

```powershell
python dev/install.py --destination "$HOME/.agents/skills/pwsh-ssh-bridge"
```

安装器要求目标目录尚不存在，只复制运行文件。升级和其他宿主目录的处理见开发指南。

随后对 Codex 说：

> 使用 $pwsh-ssh-bridge 连接我的 Linux。先检查本机环境，复用已经获准使用的连接信息，
> 每一步告诉我是在本机还是 Linux 的哪个终端操作。

Codex 会自动发现技能；未出现时重启。已有环境可能使用不同技能目录，以宿主实际报告为准，
避免同名重复安装。参见[官方技能文档](https://developers.openai.com/codex/skills)。

## 从哪里开始

1. Agent 阅读 [SKILL.md](SKILL.md)，中文完整入口见[使用指引](references/guide.zh-CN.md)。
2. 首次连接：按[双端配置](references/setup.zh-CN.md)选择已有终端和接入路径。
3. 已经连通：阅读[操作指南](references/operations.zh-CN.md)。
4. 某一步失败：查[故障诊断](references/troubleshooting.zh-CN.md)。
5. 理解原理：阅读[脱敏实战案例](references/case-study.zh-CN.md)与[研究及来源](references/research.zh-CN.md)。

所有主要文档均提供完整中英文版本。

## 设计要点

- 先观察环境，明确当前执行账户和实际使用的工具。
- 通过独立可信渠道核验服务器身份。
- 使用标准输入传递远端脚本，减少多层 shell 引号和编码问题。
- 返回有大小限制的结构化结果，明确标识超时和结果不确定。
- 将凭据保留在本机，使用 harness 提供的权限申请机制。
- 按需重新连接，并逐项验证操作结果。

脚本保持小而明确；账户选择、目标范围、服务变更与授权由用户任务决定。
本地转发绑定回环地址。文件传输要求显式覆盖参数，建议以唯一临时文件作为接收目标。

## 完整开发工作区

克隆仓库或从 Releases 下载对应版本的 `*-workspace.zip`。默认分支包含全部运行源码、测试、
双语指南、Agent 接手说明、构建工具与 CI。Agent 可以在这个目录完成修改、验证、重新打包和本地部署。

```sh
git clone https://github.com/HNNUYUXUAN/pwsh-ssh-bridge.git
cd pwsh-ssh-bridge
python dev/build.py --check
python -m unittest discover -s dev -p 'test_*.py' -v
python dev/build.py
```

Python 3.10+ 仅使用标准库。运行行为测试需要 PowerShell 7.2+ 和 OpenSSH。
两种 ZIP 与 SHA256 清单生成在 `dist/`。
完整流程见[开发指南](https://github.com/HNNUYUXUAN/pwsh-ssh-bridge/blob/main/docs/development.zh-CN.md)，
包括源码地图、测试、安装、发布和 Agent 接手。只有运行包的安装环境，可以在用户要求二次开发时
取得对应版本的工作区。

## 许可证

[MIT](LICENSE)。外部项目用于研究设计取舍，本仓库代码和文档独立编写；引用项目保留各自许可证。
