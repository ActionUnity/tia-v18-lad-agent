<!-- markdownlint-disable MD013 -->

# 复制即用说明

更新时间：2026-07-04

这个 harness 的目标很简单：**复制到任意 TIA Portal V18 `.ap18` 项目旁边，就能按固定入口做只读发现、导出、解析、受控导入、编译和保存。**

`RELEASE_MANIFEST.json` 是这个 portable 包的“身份证 + 复制检查清单”。它不是复杂发版流程，也不代表某个具体 PLC 项目的业务逻辑。

## 1. release manifest 是干什么的

它回答 5 个问题：

1. **这包是什么版本？**
   - 例如 `0.3.0-portable`。
2. **它适用于什么？**
   - TIA Portal V18、`.ap18`、Siemens Openness PublicAPI V18。
3. **复制时哪些文件不能漏？**
   - 例如 `AGENTS.md`、`harness.json`、`scripts/`、`tools/bin/AiPlcTiaV18.exe`、`AiPlcTiaV18.Core.dll`。
4. **复制后先跑什么检查？**
   - 例如 `Test-HarnessOffline.ps1`、`Probe`、`ListSessions`。
5. **哪些事永远不能自动做？**
   - 例如下载到 PLC/HMI、go online、force variables、自动改 F 块、未备份删除生产块。

所以它不是为了“发布给客户”才有，而是为了防止以后出现这些问题：

- 只复制了 `scripts/`，漏了 `tools/bin/`；
- 不知道哪个 portable 包是当前推荐包；
- 不知道复制后该先跑哪个验证；
- 不知道这个包是通用 harness，还是某个项目专用 profile；
- 修改了脚本或二进制后，没有同步版本和 hash。

## 2. 推荐复制方式

推荐用安装脚本：

```powershell
cd "D:\HarnessPackages\tia-v18-lad-agent-portable"
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\TiaProjectWorkdir"
```

目标项目旁边应该得到类似结构：

```text
D:\Your\TiaProjectWorkdir\
  YourProject.ap18
  tia-v18-lad-agent\
    AGENTS.md
    README.md
    harness.json
    RELEASE_MANIFEST.json
    COPY_USE.md
    scripts\
    tools\bin\AiPlcTiaV18.exe
    tools\bin\AiPlcTiaV18.Core.dll
    workspace\
```

如果手工复制，也要复制整个 `tia-v18-lad-agent-portable` 文件夹，不要只复制 `scripts/`。

不需要复制源码开发树：

```text
openness/code/AiPlcTiaV18/
```

`code/AiPlcTiaV18/` 只在修改 harness 源码、重新构建 `AiPlcTiaV18.exe` / `AiPlcTiaV18.Core.dll`、调试或重新制作 portable 包时才需要。普通项目使用只需要 portable 包。

## 3. 复制后第一步做什么

进入复制后的 harness 目录：

```powershell
cd "D:\Your\TiaProjectWorkdir\tia-v18-lad-agent"
```

先做离线自检：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

这一步不写 TIA 项目，只检查包本身是否完整、脚本和 runtime 是否存在。

## 4. 连接 TIA 前提

1. 目标 `.ap18` 项目已经用 TIA Portal V18 打开。
2. 当前 Windows 用户属于 `Siemens TIA Openness` 用户组。
3. 如果刚加入用户组，需要注销/重新登录。
4. 不要同时打开多个容易混淆的生产项目；如果多个 TIA 会话同时打开，后续必须指定 PID。

## 5. 只读发现流程

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
```

导出块前，不要猜块路径；先用 `ListBlocks` 或 `FindBlock` 找真实名称。

## 6. 写入原则

写入不是默认动作。任何导入/编译/保存都必须满足：

- 明确目标 PID；
- 明确目标 `.ap18` 路径或项目名；
- 明确导入对象；
- 有当前导出基线和 hash；
- 有待导入文件的 expected hash；
- 命令带 `-AllowWrite`；
- 编译成功后再单独考虑保存。

`ImportCompile` 只导入并编译，不自动保存。`SaveProject` 是单独命令。

## 7. 它不是干什么的

这个 portable 包不是：

- 某个具体项目的当前 PLC 事实源；
- V19/V20/V21 的通用工具；
- 可以随便自动生成 raw LAD/FlgNet XML 的工具；
- 可以直接下载到 PLC、online、force variable 的工具；
- 可以绕过人工确认修改安全/F 块的工具。

项目专用信息应放在独立 profile 里，不要混进 portable harness 核心。
