<!-- markdownlint-disable MD013 -->

# TIA V18 LAD Agent Harness

[中文说明](README.zh-CN.md) | English

**Copy it next to a Siemens TIA Portal V18 project and give your coding agent a safe, repeatable way to inspect, export, edit, import, compile, and save PLC work through Openness.**

This package is built for one practical goal:

```text
Copy folder → open a .ap18 project in TIA Portal V18 → run guarded harness commands
```

No source-tree setup. No hunting for scripts. No free-form XML guessing. The harness ships with a small bundled runner so a target machine can start with validation and discovery immediately.

> This project is not affiliated with, endorsed by, or sponsored by Siemens. Siemens, TIA Portal, SIMATIC, and related names are trademarks of their respective owners.

---

## Why this exists

AI agents are good at editing files, but TIA Portal projects are not ordinary text repositories. A safe Openness workflow needs more than "generate XML and import it".

This harness gives agents a controlled operating contract:

- discover the currently open TIA V18 project;
- export real TIA XML before editing;
- parse LAD/XML evidence before patching;
- keep write operations behind explicit gates;
- compile after import;
- save only after clean, fresh, matching compile evidence;
- avoid online, download, force, and safety/F-block operations.

The result is a copyable project-side harness for real-world engineering workflows where evidence matters.

---

## What you get

```text
tia-v18-lad-agent-portable/
  AGENTS.md                         # agent operating contract
  README.md                         # this public overview
  README.zh-CN.md                   # Chinese overview
  COPY_USE.md                       # short Chinese copy-and-use guide
  RELEASE_MANIFEST.json             # package identity + required files + hashes
  LICENSE                           # MIT license
  harness.json                      # machine-readable command map
  scripts/                          # guarded PowerShell wrappers
  tools/bin/AiPlcTiaV18.exe          # bundled Openness CLI runner
  tools/bin/AiPlcTiaV18.Core.dll     # bundled Openness core runtime
  docs/                             # safety gates and command docs
  schemas/                          # action/patch schemas
  templates/                        # reviewed template/catalog placeholders
  examples/                         # neutral motor examples and parser fixtures
  workspace/                        # local generated exports/reports/evidence
```

---

## Quick start

### 1. Copy or install the harness

Recommended:

```powershell
cd "D:\HarnessPackages\tia-v18-lad-agent-portable"
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\TiaProjectWorkdir"
```

Expected result:

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

Manual copy also works, but copy the whole folder. Do not copy only `scripts/`.

### 2. Validate the copied package

From the copied harness root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

This checks the local package shape, required scripts, schemas, runtime files, examples, and offline safety gates. It does not write to a TIA project.

### 3. Open your project in TIA Portal V18

Make sure:

- TIA Portal V18 is installed;
- Openness is installed and enabled;
- the Windows user is in the `Siemens TIA Openness` group;
- the target `.ap18` project is already open in TIA Portal V18.

### 4. Discover the open project

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
```

Do not guess block paths. Use block names/paths discovered from the open project.

---

## Why are binaries included?

The bundled files are intentional:

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

They are included because this package is designed for **copy-and-use operation**. A machine that receives the harness should not need the original source tree, Visual Studio, MSBuild setup, or a separate build step before it can run `Probe`, `ListSessions`, `ExportBlock`, `ImportCompile`, or `SaveProject`.

Can you omit them? Technically yes, but then this is no longer a copy-and-use package. Without the binaries, users must build or provide matching `AiPlcTiaV18` runtime files themselves and update `RELEASE_MANIFEST.json` hashes.

For this portable distribution, the binaries stay in the package and are tracked by SHA256 in `RELEASE_MANIFEST.json`.

No Siemens runtime DLLs are bundled. The target machine must have Siemens TIA Portal V18 and Openness installed.

---

## Safety model

This harness is intentionally conservative.

It does **not** automatically:

- download to PLC/HMI;
- go online;
- force variables;
- modify safety/F blocks;
- delete production blocks;
- save after a failed compile;
- import arbitrary raw FlgNet XML generated from free-form text.

Write operations require explicit intent and project identity checks such as:

```text
-AllowWrite
-ExpectedProjectPath <approved .ap18 path>
```

`ImportCompile` imports and compiles, but it does not save. `SaveProject` is a separate guarded command that requires fresh, matching, zero-error compile evidence.

---

## Typical agent loop

```text
Probe
→ ListSessions
→ AttachSummary
→ ListBlocks / FindBlock
→ ExportBlock
→ ParseLad or ParseDb
→ Patch current exported XML or use a reviewed template
→ CleanXml / ValidateXml
→ ImportCompile with explicit write approval
→ Read back / verify
→ SaveProject only after clean evidence
```

The package is designed so an agent can follow this loop without asking the user to manually run low-level Openness commands.

---

## What this package is not

This is not:

- a TIA Portal replacement;
- a Siemens product;
- a downloader or online monitor;
- a safety-program editing tool;
- a universal TIA version bridge;
- a place to store project-specific exports, evidence, or customer logic.

Project-specific facts belong in a separate private profile. The portable harness should remain generic.

---

## Important files

| File | Purpose |
| --- | --- |
| `COPY_USE.md` | Short Chinese copy-and-use guide. |
| `RELEASE_MANIFEST.json` | Version, required files, hashes, first commands, safety boundaries. |
| `AGENTS.md` | Main agent operating contract. |
| `harness.json` | Machine-readable command and tool map. |
| `docs/validation-gates.md` | Write/save gate explanation. |
| `docs/editing-contract.md` | What kinds of XML edits are allowed. |
| `scripts/Invoke-TiaV18LadHarness.ps1` | Main guarded command wrapper. |
| `scripts/Test-HarnessOffline.ps1` | Offline package validation. |
| `scripts/Test-HarnessLiveRoundTrip.ps1` | Live discovery/read/write-gate validation helper. |

---

## Workspace policy

The `workspace/` folder is for generated local artifacts after the harness is copied next to a project:

```text
workspace/exports/
workspace/patched/
workspace/reports/
workspace/evidence/
```

These folders can contain real project XML, compile evidence, logs, screenshots, or paths. They are ignored by `.gitignore` and should not be published unless you intentionally want to share a sanitized fixture.

---

## License

MIT. See `LICENSE`.

This package does not include Siemens software or Siemens engineering libraries. Users must have their own licensed TIA Portal V18 installation with Openness available.
