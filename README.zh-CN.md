<!-- markdownlint-disable MD013 -->

# TIA V18 LAD Agent Harness

**把 AI 编程代理变成有护栏的 Siemens TIA Portal V18 LAD 操作员。**

把这个文件夹复制到任意 `.ap18` 工程旁边，打开 TIA Portal V18，就能让你的代理沿着一条可复核、可重复、可追踪的 Openness 路线完成工程发现、XML 导出、LAD 编辑、导入、编译和受控保存。

**不需要源码树。不需要 Visual Studio 环境。不需要让 AI 凭空猜 XML。**

这是一个面向真实 PLC 工程现场的 portable harness：复制即用，默认保守，证据优先。

English: [`README.md`](./README.md)

> 本项目不是 Siemens 官方项目，也未获得 Siemens 赞助、背书或授权。Siemens、TIA Portal、SIMATIC 等名称归其各自权利人所有。

---

## 一句话定位

AI 写代码很快，但 PLC 工程不能只靠“写得快”。

TIA Portal 工程不是普通文本仓库，LAD XML 也不是随便拼一段就能安全导入的格式。如果你想让 AI 帮你处理 Siemens TIA Portal V18 工程，你需要的不是一个零散脚本，而是一条受控跑道：

- 找到真实打开的 TIA 工程；
- 编辑前先导出真实 XML；
- 基于当前证据修改，而不是凭空生成；
- 写入必须经过显式闸门；
- 导入后立即编译；
- 只有在新鲜、匹配、零错误的编译证据下才允许保存；
- 默认不联机、不下载、不强制变量、不碰安全/F 块。

**这个 harness 就是给 AI 代理用的 TIA V18 LAD 安全跑道。**

---

## 为什么值得下载

### 1. 真正复制即用

下载文件夹，放到 TIA V18 `.ap18` 工程旁边，运行离线检查，打开 TIA Portal，就能开始发现工程。

包里已经带好运行器：

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

所以使用者不需要先找源码、不需要现场搭建 C# 构建环境、不需要重新编译工具，才能跑第一条 Openness 命令。

### 2. 给 AI 权力，也给 AI 边界

代理不是“直接改 PLC”。它必须沿着文档化流程走：

```text
Probe → ListSessions → AttachSummary → ExportBlock → Parse → Patch → Validate → ImportCompile → Verify → SaveProject
```

每一步都有名字、有脚本、有文档、有证据。

### 3. LAD 优先，适合工程人员查看

这个包面向 TIA Portal V18 LAD XML round-trip。默认保持 FB/FC 最终交付语言为 LAD，便于工程人员在 TIA Portal 里监看、审查和维护。

### 4. 不是演示优先，而是安全优先

默认只读。写入需要明确参数和工程身份约束。导入/编译不等于保存。保存是单独的受控命令。联机、下载、强制变量、安全/F 块操作都不在自动化范围内。

### 5. 对各种 Agent 友好

包里带了 `AGENTS.md`、`harness.json`、schema、命令文档，以及多种代理入口文件。换一个代理，也能快速理解“应该怎么做、不应该怎么做”。

---

## 60 秒理解它

```text
你的 TIA V18 工程
        │
        │  复制/安装
        ▼
tia-v18-lad-agent/
        │
        ├─ 告诉 AI 哪些事允许做
        ├─ 发现当前打开的 TIA 会话
        ├─ 从真实工程导出 XML
        ├─ 在本地验证和修改 XML
        ├─ 只在明确授权后导入
        ├─ 编译并记录证据
        └─ 只在证据干净时受控保存
```

一句话：**让 AI 能干活，但不让它乱来。**

---

## 快速开始

### 第 1 步：复制或安装 harness

推荐使用安装脚本：

```powershell
cd "D:\HarnessPackages\tia-v18-lad-agent-portable"
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\TiaProjectWorkdir"
```

目标目录会类似这样：

```text
D:\Your\TiaProjectWorkdir\
  YourProject.ap18
  tia-v18-lad-agent\
    AGENTS.md
    README.md
    README.zh-CN.md
    harness.json
    scripts\
    tools\bin\AiPlcTiaV18.exe
    tools\bin\AiPlcTiaV18.Core.dll
    workspace\
```

也可以手工复制，但请复制整个文件夹，不要只复制 `scripts/`。

### 第 2 步：运行离线检查

在复制后的 harness 根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

这个命令会检查包结构、必需文件、schema、示例、随包运行器、workspace 清洁度，以及离线安全回归。它不会写入 TIA 工程。

### 第 3 步：打开 TIA Portal V18 工程

请确认：

- 已安装 Siemens TIA Portal V18；
- 已安装并启用 Siemens TIA Openness V18；
- 当前 Windows 用户具备 Openness 权限；
- 目标 `.ap18` 工程已经在 TIA Portal V18 中打开。

### 第 4 步：发现当前工程

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
```

后续应使用工具发现到的块名和路径，不要猜路径。

---

## 包里有什么

```text
tia-v18-lad-agent-portable/
  AGENTS.md                         # 代理主操作契约
  README.md                         # 英文 GitHub 首页
  README.zh-CN.md                   # 中文 GitHub 首页
  COPY_USE.md                       # 简短中文复制即用指南
  LICENSE                           # MIT 许可证
  RELEASE_MANIFEST.json             # 版本、必需文件、hash、安全边界
  harness.json                      # 机器可读命令地图
  scripts/                          # 受控 PowerShell 包装脚本
  tools/bin/AiPlcTiaV18.exe          # 随包 Openness CLI 运行器
  tools/bin/AiPlcTiaV18.Core.dll     # 随包 Openness 核心运行库
  docs/                             # 编辑契约、命令、安全闸门、wiki
  schemas/                          # action-plan 和 patch schema
  templates/                        # 已审查模板/目录占位
  examples/                         # 中性示例和 XML fixture
  workspace/                        # 本地导出、补丁、报告、证据
```

---

## 为什么二进制文件要随包提供

这个项目的核心承诺是：**复制即用**。

如果不带运行器二进制，使用者就必须先找到匹配源码、恢复构建环境、编译正确目标，再把输出放回 `tools/bin`。这会直接破坏“拿来就能跑”的体验。

所以 portable 包有意包含：

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

它们在 `RELEASE_MANIFEST.json` 中用 SHA256 跟踪。

你当然可以做 source-only fork，然后自己构建并提供兼容运行器。但这个发行包的定位就是复制即用，因此二进制文件保留在仓库和包内。

本包不包含 Siemens runtime DLL。使用者必须自行安装并授权 TIA Portal V18 和 Openness。

---

## 安全模型

这个 harness 故意保守。

它不会自动：

- 下载到 PLC/HMI；
- 进入在线模式；
- 强制变量；
- 修改安全/F 块；
- 删除生产块；
- 在编译失败后保存；
- 导入由自由文本凭空生成的 FlgNet XML。

写入操作需要显式闸门，例如：

```text
-AllowWrite
-ExpectedProjectPath <approved .ap18 path>
```

`ImportCompile` 负责导入并编译，但不保存。`SaveProject` 是独立的受控命令，必须看到新鲜、匹配、零错误的编译证据才会放行。

---

## 它和普通脚本文件夹有什么区别

| 普通脚本文件夹 | 这个 harness |
| --- | --- |
| 几个命令散落在文档里 | 完整代理操作契约 |
| 容易跑错目标 | 读/写/保存闸门明确 |
| 假设工程结构 | 从 TIA 会话发现工程和块 |
| 容易凭空生成 XML | 从真实导出的 TIA XML 开始 |
| 编译和保存逻辑随意 | 编译证据解锁受控保存 |
| 换一个代理就看不懂 | 多代理入口、schema、命令地图齐全 |

---

## 适合什么场景

适合让代理协助：

- 查看 LAD 块；
- 导出和解析 LAD XML；
- 基于当前工程导出的 XML 做边界明确的 LAD 修改；
- 处理 Global DB、UDT、tag table 等 XML 工作流；
- 执行导入后立即编译的受控循环；
- 在本地保存工程证据、报告和回读结果。

不适合：

- 在线调试；
- 强制值；
- PLC/HMI 下载；
- 安全/F 程序编辑；
- 未审查兼容性的其它 TIA 版本。

---

## Agent 从哪里开始读

推荐入口：

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`
5. `schemas/action-plan.schema.json`
6. `templates/verified-template-catalog.json`

给代理的短版规则：

```text
使用当前打开的 TIA V18 工程。
编辑前必须导出。
只能修改当前证据或已审查模板。
写入必须明确授权。
导入后立即编译。
保存必须依赖干净的受控证据。
绝不下载、联机、强制变量或修改安全/F 块。
```

---

## Workspace 策略

`workspace/` 是本地运行时目录：

```text
workspace/exports/
workspace/patched/
workspace/reports/
workspace/evidence/
```

实际使用后，这些目录可能包含真实工程 XML、编译证据、报告、日志或工程路径。它们已经被 `.gitignore` 忽略，除非你主动清洗并准备公开 fixture，否则不要发布。

---

## 如果你也有这些痛点，值得 Star / 下载

- 你想让 AI 帮你处理工业自动化工程，但又不想让它失控；
- 你需要另一个代理明天也能接手同一套 Openness 流程；
- 你希望最终逻辑保持 LAD，方便工程人员在 TIA Portal 里查看；
- 你关心编译证据、工程身份和受控保存；
- 你厌倦了一堆只能在本机复现的临时脚本；
- 你想要一个可以复制到工程旁边就能跑的标准化工具包。

---

## 许可证和商标说明

MIT。见 [`LICENSE`](./LICENSE)。

本项目不是 Siemens 官方项目，也未获得 Siemens 赞助、背书或授权。Siemens、TIA Portal、SIMATIC 等名称归其各自权利人所有。

本包不包含 Siemens 软件或 Siemens 工程库。使用者必须自行提供已授权的 TIA Portal V18 安装，并确保 Openness 可用。
