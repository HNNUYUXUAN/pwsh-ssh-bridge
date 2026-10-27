# 研究与来源

[English](research.md)

检索日期为 2026-10-26 至 27。优先通过腾讯元宝搜索发现资料，通过 GitHub 连接工具读取仓库内容和元数据，
协议与平台行为以抓取的官方资料为依据，社区资料用于启发排查问题与形成待验证假设。

## 开源 skill / 工具比较

| 来源快照 | 值得借鉴的设计证据 | 在本项目中的应用 |
|---|---|---|
| [ssh-remote-dev，58e1cf4](https://github.com/rogue-shadowdancer/codex-skill-ssh-remote-dev/blob/58e1cf4bea23631997eee5fed968784b16824c2d/SKILL.md) | 面向 Windows 的远端检查与本地暂存、编辑、上传流程，明确关注沙箱身份 | 加入暂存编辑、实际执行身份检查和宿主支持的权限路径 |
| [ssh-skill，c6c8a18](https://github.com/kyaring/ssh-skill/blob/c6c8a184a7d8c8b217860a015f5860418647d8ea/SKILL.md) | 结构化结果、有界输出、未知结果和避免命令重放 | 明确 JSON 字段，限制流捕获量，保守处理超时 |
| [AgentSSH，ed0780a](https://github.com/trtyr/AgentSSH/blob/ed0780afc99c2027e7ab8b84a0e1dc230819db0f/SKILL.md) | 区分单次执行、交互/会话操作和端口转发 | 将单次命令成功、持久任务与真正的端口隧道分别说明 |

它们是独立外部实现，不是本项目经过测试的依赖。
检索时仓库元数据显示 ssh-remote-dev 使用 LGPL-2.1、AgentSSH 使用 MIT；ssh-skill 的 GitHub 元数据未识别许可证。
本包不包含这些项目的源代码或 skill 原文。链接固定研究快照，后续版本可能变化。

本项目使用独立编写的 PowerShell/.NET 运行器和操作系统 OpenSSH。
首次配置流程来自实战证据：检查双端环境、利用既有可信入口安装公钥、切换网络路径时保持身份验证，
并在 harness 的真实执行账户下重新验证。

## 使用的主要原始文档

- [Codex skills](https://developers.openai.com/codex/skills)：技能发现、SKILL.md、可选资源及当前用户技能目录。
  网页工具无法渲染 Markdown 格式后，通过官方 `.md` 入口抓取完整内容。
- [Codex Windows](https://developers.openai.com/codex/windows)：本地终端、文件系统、网络权限和执行身份独立于远端 SSH 授权。
- [OpenSSH ssh_config](https://man.openbsd.org/ssh_config)：先取得的配置值优先、HostKeyAlias、严格主机核验、批处理、保活与转发控制。
- [OpenSSH ssh-keyscan](https://man.openbsd.org/ssh-keyscan)：收集密钥不等于认证来源，需要可信渠道核验。
- [OpenSSH scp](https://man.openbsd.org/scp)：现代 scp 使用 SFTP，路径与失败状态仍需明确处理。
- [Microsoft OpenSSH 密钥管理](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)：
  密钥/agent 流程和 Windows 凭据处理。
- [ProcessStartInfo.ArgumentList](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.argumentlist)：
  以独立参数传给本地进程，避免拼接 shell 命令字符串。
- [OpenBSD PF 重定向与回环](https://www.openbsd.org/faq/pf/rdr.html)：
  解释同网段回复绕过转换网关时，TCP 握手为何可能失败。

## 论坛经验及证据边界

元宝检索发现了 Server Fault 的
[“Loopback to forwarded Public IP address from local network – Hairpin NAT”讨论](https://serverfault.com/questions/73237/loopback-to-forwarded-public-ip-address-from-local-network-hairpin-nat)
及[相关回答](https://serverfault.com/a/729252)。搜索摘录描述了同网段地址转换问题。
本轮未能直接读取论坛页面，因此未转载论坛原文或防火墙规则；技术解释以本案例和可读取的 OpenBSD 原始文档为依据。

可借鉴的排查方法是对照客户端状态、代理上游日志和服务端报文证据，而不是在所有环境中添加 NAT 规则。
服务商管理的网络需要结合网络所有者掌握的上下文与授权处理。

## 独立实现与验证

本项目代码、配置流程和双语文档均为此工作流独立编写。
本地与实机测试验证可观察行为，具体范围及限制见[验证记录](verification.zh-CN.md)。
外部项目的描述属于设计参考，不构成本项目对相应环境的兼容性承诺。
