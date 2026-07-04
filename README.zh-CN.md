<!-- markdownlint-disable MD013 -->

# TIA V18 LAD Agent Harness

中文说明 | English: `README.md`

**把它复制到 Siemens TIA Portal V18 工程旁边，让 AI 编程代理用一套安全、可复核、可重复的流程完成 PLC 工程的发现、导出、编辑、导入、编译和受控保存。**

这个项目的目标很直接：

```text
复制文件夹 → 在 TIA Portal V18 中打开 .ap18 工程 → 运行受保护的 harness 命令
```

不需要携带源码树，不需要现场找脚本，不需要让代理凭空生成 XML。这个 portable 包已经带了一个小型运行器，复制到目标机器后就可以立即做环境验证和工程发现。

> 本项目不是 Siemens 官方项目，也未获得 Siemens 赞助、背书或授权。Siemens、TIA Portal、SIMATIC 等名称归其各自权利人所有。

---

## 为什么需要它

AI 代理很擅长编辑文件，但 TIA Portal 工程不是普通文本仓库。安全使用 Openness 需要的不只是“生成一段 XML 再导入”。

这个 harness 给代理提供一套受控工作契约：

- 发现当前打开的 TIA V18 工程；
- 编辑前先导出真实 TIA XML；
- 修改前解析 LAD/XML 证据；
- 所有写入动作都经过显式闸门；
- 导入后立即编译；
- 只有在编译证据新鲜、匹配且零错误时才允许保存；
- 避免联机、下载、强制变量和安全/F 块操作。

它面向的是工程现场常见的需求：让代理能干活，但每一步都留下证据，并且默认保守。

---

## 包里有什么

```text
tia-v18-lad-agent-portable/
  AGENTS.md                         # 代理操作契约
  README.md                         # 英文 GitHub 首页说明
  README.zh-CN.md                   # 中文说明
  COPY_USE.md                       # 简短中文复制即用指南
  RELEASE_MANIFEST.json             # 包身份、必需文件、hash、安全边界
  LICENSE                           # MIT 许可证
  harness.json                      # 机器可读命令地图
  scripts/                          # 受保护 PowerShell 包装脚本
  tools/bin/AiPlcTiaV18.exe          # 随包提供的 Openness CLI 运行器
  tools/bin/AiPlcTiaV18.Core.dll     # 随包提供的核心运行库
  docs/                             # 安全闸门和命令文档
  schemas/                          # action/patch schema
  templates/                        # 已审查模板/目录占位
  examples/                         # 中性示例和解析 fixture
  workspace/                        # 本地产生的导出、报告和证据目录
```

---

## 快速开始

### 1. 复制或安装 harness

推荐方式：

```powershell
cd "D:\HarnessPackages\tia-v18-lad-agent-portable"
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\TiaProjectWorkdir"
```

目标目录会变成类似这样：

```text
D:\Your\TiaProjectWorkdir\
  YourProject.ap18
  tia-v18-lad-agent\
    AGENTS.md
    README.md
    harness.json
    scripts\
    tools\bin\AiPlcTiaV18.exe
    tools\bin\AiPlcTiaV18.Core.dll
    workspace\
```

也可以手工复制，但必须复制整个文件夹。不要只复制 `scripts/`。

### 2. 验证 portable 包

在复制后的 harness 根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

这个命令会检查包结构、必需脚本、schema、运行文件、示例、workspace 状态和离线安全闸门。它不会写入 TIA 工程。

### 3. 打开 TIA Portal V18 工程

确认：

- 已安装 TIA Portal V18；
- 已安装并启用 Openness；
- 当前 Windows 用户在 `Siemens TIA Openness` 用户组中；
- 目标 `.ap18` 工程已经在 TIA Portal V18 中打开。

### 4. 发现当前打开的工程

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
```

不要猜块路径。必须使用工具从当前打开工程里发现到的实际块名和路径。

---

## 为什么二进制随包提供

下面两个文件是有意随包提供的：

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

原因很简单：这个包的定位是**复制即用**。拿到 harness 的机器不应该还需要源码树、Visual Studio、MSBuild 配置或额外构建步骤，才能运行 `Probe`、`ListSessions`、`ExportBlock`、`ImportCompile` 或 `SaveProject`。

可以不提供它们吗？技术上可以，但那样这个项目就不再是复制即用包。用户需要自己构建或提供匹配版本的 `AiPlcTiaV18` 运行文件，并同步更新 `RELEASE_MANIFEST.json` 里的 hash。

所以在这个 portable 发行方式里，二进制保留在包内，并由 `RELEASE_MANIFEST.json` 记录 SHA256。

本包不包含 Siemens 运行库 DLL。目标机器必须自己安装并授权 TIA Portal V18 和 Openness。

---

## 安全模型

这个 harness 默认保守。

它不会自动执行：

- 下载到 PLC/HMI；
- 联机；
- 强制变量；
- 修改安全/F 块；
- 删除生产块；
- 编译失败后保存；
- 导入由自然语言随意生成的原始 FlgNet XML。

写入操作必须带有显式意图和工程身份校验，例如：

```text
-AllowWrite
-ExpectedProjectPath <approved .ap18 path>
```

`ImportCompile` 负责导入并编译，但不会保存。`SaveProject` 是单独的受控命令，只有在存在新鲜、匹配、零错误的编译证据时才会执行。

---

## 典型代理工作流

```text
Probe
→ ListSessions
→ AttachSummary
→ ListBlocks / FindBlock
→ ExportBlock
→ ParseLad 或 ParseDb
→ 基于当前导出的 XML 打补丁，或使用已审查模板
→ CleanXml / ValidateXml
→ 带显式写入批准执行 ImportCompile
→ 回读 / 验证
→ 只有证据干净时才 SaveProject
```

这个包的设计目标是：让代理自动完成低层 Openness 操作，而不是让人手工复制 PID、导出 XML、导入 XML 或编译。

---

## 它不是什么

它不是：

- TIA Portal 替代品；
- Siemens 官方产品；
- 下载器或联机监视器；
- 安全程序编辑工具；
- 通用 TIA 版本桥；
- 存放项目专用导出、证据或客户逻辑的地方。

项目专用事实应该放在独立的私有 profile 里，portable harness 本身应保持通用。

---

## 重要文件

| 文件 | 用途 |
| --- | --- |
| `COPY_USE.md` | 简短中文复制即用指南。 |
| `RELEASE_MANIFEST.json` | 版本、必需文件、hash、首个命令和安全边界。 |
| `AGENTS.md` | 代理主操作契约。 |
| `harness.json` | 机器可读命令和工具地图。 |
| `docs/validation-gates.md` | 写入和保存闸门说明。 |
| `docs/editing-contract.md` | 允许哪些 XML 编辑方式。 |
| `scripts/Invoke-TiaV18LadHarness.ps1` | 主受控命令包装脚本。 |
| `scripts/Test-HarnessOffline.ps1` | 离线包验证。 |
| `scripts/Test-HarnessLiveRoundTrip.ps1` | 现场发现/读写闸门验证辅助脚本。 |

---

## Workspace 策略

`workspace/` 用于 harness 复制到工程旁边后产生本地工件：

```text
workspace/exports/
workspace/patched/
workspace/reports/
workspace/evidence/
```

这些目录可能包含真实工程 XML、编译证据、日志、截图或路径。它们已被 `.gitignore` 忽略，不应该公开上传，除非你明确准备发布已经脱敏的 fixture。

---

## 许可证

MIT。详见 `LICENSE`。

本包不包含 Siemens 软件或 Siemens 工程库。用户必须自行拥有已授权的 TIA Portal V18 安装，并启用 Openness。
