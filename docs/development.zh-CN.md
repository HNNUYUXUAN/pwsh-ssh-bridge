# 开发工作区

[English](development.md)

本仓库默认分支就是完整的本地开发工作区。运行脚本、Agent 指引、测试、构建工具与研究材料
共同纳入版本管理。二次开发时克隆仓库；日常安装可下载 Release 的 skill ZIP。
两种 ZIP 都由这里的同一份源码生成。

## 在新机器上开始

1. 安装 Git、Python 3.10+ 和 PowerShell 7.2+。分别检查 `git --version`、
   `python --version` 和 `pwsh -NoProfile -Command '$PSVersionTable.PSVersion'`。
   Python 构建工具只使用标准库，无需 pip 安装依赖。
2. 把仓库克隆到可写的开发目录：

   ```sh
   git clone https://github.com/HNNUYUXUAN/pwsh-ssh-bridge.git
   cd pwsh-ssh-bridge
   python dev/build.py --check
   python -m unittest discover -s dev -p 'test_*.py' -v
   python dev/build.py
   ```

3. 修改运行脚本前，检查本机 OpenSSH 工具：

   ```powershell
   pwsh -NoProfile -File ./scripts/Test-BridgeEnvironment.ps1
   ```

   SSH 本地测试需要 `ssh` 和 `ssh-keygen`；实机文件传输测试需要 OpenSSH 9+ 及服务端 SFTP。
   缺依赖时按[配置指南](../references/setup.zh-CN.md)处理。遇到沙箱或 ACL 问题，
   使用 harness 支持的权限机制，在预期的操作系统账户下运行。
4. 把测试临时目录放在仓库以外，运行本地测试：

   ```powershell
   $scratch = Join-Path ([IO.Path]::GetTempPath()) ('bridge-tests-' + [guid]::NewGuid().ToString('N'))
   pwsh -NoProfile -File ./tests/Test-Local.ps1 -WorkDirectory $scratch
   if ($LASTEXITCODE -ne 0) { throw '本地测试失败' }
   ```

测试会在输出的临时路径保留一次性密钥和诊断文件。请保持该目录私有；不再需要诊断时，
核实绝对路径后清理这一个目录。构建和打包测试不连接远端服务器。

## 源码地图

| 路径 | 职责 |
|---|---|
| `SKILL.md`、`agents/` | Agent 入口和 Codex 发现元数据 |
| `scripts/Bridge.Common.psm1` | 子进程、输出限制、结果语义及参数检查 |
| 其他 `scripts/` | 环境、密钥初始化、SSH 配置、执行、传输、隧道 |
| `references/` | 完整中英文配置、操作、诊断、研究与验证材料 |
| `tests/` | 本地行为测试及按需运行的 Linux 集成测试 |
| `dev/build.py` | 明确的打包清单、检查、可重复构建的 ZIP 和校验值 |
| `dev/install.py` | 向新的本地技能目录安装运行文件 |
| `dev/test_build.py` | 构建可重复性、解压重建及安装行为测试 |
| `.github/workflows/ci.yml` | GitHub 上的 Windows 本地测试与打包 |
| `AGENTS.md`、`docs/` | Agent 接手说明、开发及发布指引 |

## 修改、测试、安装

在主题分支中开发，运行行为与相应指南一起修改，中英文同步。为发生变化的可观察行为添加
回归测试。打包修改运行 Python 测试，运行脚本修改运行 PowerShell 本地测试，部署前检查差异。

从已经检查过的源码安装到 harness 报告的一个**新目录**：

```powershell
python dev/install.py --destination "$HOME/.agents/skills/pwsh-ssh-bridge"
```

安装器只复制运行文件，已有目标会被拒绝。更新前保留本地修改，把旧安装移动到所有可发现
技能目录之外的已确认备份位置，再安装新版。必要时让 harness 重新扫描或重启。
在实际安装目录运行环境检查；只针对用户已授权的目标做一次认证探测。保留源码目录以便继续开发。

## 实机集成测试

运行前阅读 [Test-Live.ps1](../tests/Test-Live.ps1)。目标与临时测试操作需要用户授权。
传入已有、已审查的配置；仓库不携带连接凭据：

```powershell
pwsh -NoProfile -File ./tests/Test-Live.ps1 `
  -ConfigFile '<私有配置目录>/ssh_config' -Alias lab -WorkDirectory '<私有临时目录>'
```

测试要求 Linux 提供 `sh`、`mktemp`、`sha256sum`、`stat`、SFTP，且远端回环地址 22 端口
提供 SSH。它会创建唯一的远端临时目录，测试传输与转发，随后清理列出的远端文件和隧道。
本地临时密钥保留在测试目录。清理失败时需要报告并检查。CI 不会自动运行实机测试。
[验证记录](../references/verification.zh-CN.md)区分历史实机结果和本次实际执行的检查。

## 构建与发布

`python dev/build.py` 在被 Git 忽略的 `dist/` 生成：

- `pwsh-ssh-bridge-X.Y.Z-skill.zip`：可安装的技能运行目录。
- `pwsh-ssh-bridge-X.Y.Z-workspace.zip`：完整可编辑源码、测试、文档和构建工具。
- `SHA256SUMS`：两份 ZIP 的 SHA256。
- `manifest.json`：压缩包及每个规范化源码文件的校验值。

发布时更新 [VERSION](../VERSION)。文件统一 UTF-8/LF，ZIP 使用固定时间戳与权限，
不压缩存储以避开不同 zlib 版本导致的差异。打包测试会解压工作区包，再重建两份产物，
验证源码完整性。新增顶层源码目录时，需要明确加入 `dev/build.py` 的清单。
检查器会检查链接和明显的私钥头，它不等同于完整的秘密扫描工具；发布前仍需检查源码差异
和生成的压缩包中是否存在私有标识或凭据。

测试通过后提交源码，在该提交上创建 `vX.Y.Z` 标签并推送。已登录 GitHub CLI 且获得发布
授权的维护者可以上传已构建产物：

```sh
gh release create vX.Y.Z --verify-tag --title 'vX.Y.Z' --notes-file docs/release-notes.md dist/*
```

把示例版本替换为 `VERSION` 的值，先更新发布说明，上传后检查远端资产和校验值。
本地构建与安装不会发布仓库，也不会修改本机 SSH 配置。

## 交给其他 Agent 接手

可以这样下达任务：“阅读 AGENTS.md 与开发指南，检查本机工具，在这个源码目录完成指定修改，
运行对应测试，构建两种包；保留已有修改后，部署到我指定的技能目录。”

Git 仓库是长期可编辑的工作区。已安装的技能可以指引 Agent 克隆本仓库，或下载对应版本的
工作区包。执行下载代码前先确认来源和版本。其他 harness 需要自行验证终端、权限与技能发现
方式；参考实测环境是 Windows 上的 Codex、PowerShell 和 Windows OpenSSH。
