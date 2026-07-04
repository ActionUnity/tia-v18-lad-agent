<!-- markdownlint-disable MD013 MD033 -->

# TIA V18 LAD Agent Harness

<p align="center">
  <strong>Turn AI coding agents into guarded Siemens TIA Portal V18 LAD operators.</strong>
</p>

<p align="center">
  Copy the folder beside any <code>.ap18</code> project, open TIA Portal V18, and give your agent a repeatable path to discover, export, edit, import, compile, and save through Openness.
</p>

<p align="center">
  <strong>No source checkout. No Visual Studio setup. No free-form XML guessing.</strong><br />
  A portable, safety-first harness for real PLC engineering workflows.
</p>

---

## The pitch

AI can write code fast. PLC engineering needs something stricter.

TIA Portal projects are not normal text repositories, and LAD XML is not a place for blind generation. If an agent is going to help with Siemens TIA Portal work, it needs a runway:

- find the real open project;
- export real project XML before touching anything;
- patch current evidence instead of inventing structure;
- import only through explicit write gates;
- compile immediately;
- save only after fresh zero-error evidence;
- never go online, download, force, or touch safety/F-blocks by accident.

**This harness is that runway.**

It packages the command contract, PowerShell wrappers, schemas, docs, examples, workspace layout, and a bundled Openness runner into one folder an engineer can copy next to a TIA V18 project.

If your goal is "let an AI agent safely help me modify LAD logic in TIA Portal V18", this is the missing project-side operating layer.

---

## Why people download this

### 1. It is actually copy-and-use

Download or copy the folder. Put it next to a TIA V18 `.ap18` project. Run the offline check. Open TIA Portal. Start discovery.

The package already includes:

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

That means users do **not** need the source tree, Visual Studio, MSBuild, or a separate build artifact before they can run the first real checks.

### 2. It gives AI agents boundaries

An agent does not just "edit a PLC". It follows a documented loop:

```text
Probe → ListSessions → AttachSummary → ExportBlock → Parse → Patch → Validate → ImportCompile → Verify → SaveProject
```

Every important step is named, scripted, and documented.

### 3. It is built for LAD-first workflows

The harness is optimized for Siemens TIA Portal V18 LAD XML round trips. It keeps final FB/FC logic in LAD unless the user explicitly asks otherwise.

### 4. It is safety-first, not demo-first

The default mode is read-only. Write operations need explicit approval flags and project identity checks. Save is separate from import/compile. Online and download actions are out of scope.

### 5. It is agent-friendly out of the box

The package includes entry files for common coding-agent environments, plus a central `AGENTS.md` contract and `harness.json` command map.

---

## 60-second mental model

```text
Your TIA V18 project
        │
        │  copy/install
        ▼
tia-v18-lad-agent/
        │
        ├─ tells the agent what is allowed
        ├─ discovers the open TIA session
        ├─ exports real XML from the project
        ├─ validates and patches local files
        ├─ imports only with explicit write gates
        ├─ compiles and records evidence
        └─ saves only after clean guarded proof
```

The agent gets power, but the harness gives it rails.

---

## Quick start

### Step 1 — Copy or install

Recommended installer:

```powershell
cd "D:\HarnessPackages\tia-v18-lad-agent-portable"
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\TiaProjectWorkdir"
```

Expected layout:

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

Manual copy is fine too, but copy the whole folder. Do not copy only `scripts/`.

### Step 2 — Run the offline package check

From the copied harness root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

This checks package shape, required files, schemas, examples, bundled runtime files, workspace cleanliness, and offline safety regressions.

### Step 3 — Open your `.ap18` project in TIA Portal V18

Requirements:

- Siemens TIA Portal V18;
- Siemens TIA Openness V18;
- Windows user allowed to use Openness;
- target project already open in TIA Portal.

### Step 4 — Discover the project

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
```

From there, the agent should use discovered block names and paths. It should not guess.

---

## What ships in the box

```text
tia-v18-lad-agent-portable/
  AGENTS.md                         # main agent operating contract
  README.md                         # public GitHub landing page
  COPY_USE.md                       # short Chinese copy-and-use guide
  LICENSE                           # MIT license
  RELEASE_MANIFEST.json             # package version, required files, hashes
  harness.json                      # machine-readable command map
  scripts/                          # guarded PowerShell wrappers
  tools/bin/AiPlcTiaV18.exe          # bundled Openness CLI runner
  tools/bin/AiPlcTiaV18.Core.dll     # bundled Openness core runtime
  docs/                             # editing contract, commands, gates, wiki
  schemas/                          # action-plan and patch schemas
  templates/                        # reviewed template/catalog placeholders
  examples/                         # neutral examples and XML fixtures
  workspace/                        # generated exports, patches, reports, evidence
```

---

## Why the binaries stay in the repository

This package is designed to be copied into engineering workdirs and used immediately.

If the runner binaries are missing, every user must first find the matching source tree, restore the build environment, compile the correct target, and place the output back into `tools/bin`. That destroys the core promise of the project.

So the portable package intentionally includes:

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

They are tracked in `RELEASE_MANIFEST.json` with SHA256 hashes.

You can remove them for a source-only fork, but then you must rebuild and provide compatible runtime files yourself. For this distribution, the binaries are part of the copy-and-use experience.

No Siemens runtime DLLs are bundled. Users must have their own licensed TIA Portal V18 installation with Openness available.

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

Write operations require explicit gates such as:

```text
-AllowWrite
-ExpectedProjectPath <approved .ap18 path>
```

`ImportCompile` imports and compiles, but it does not save. `SaveProject` is a separate guarded command that requires fresh, matching, zero-error compile evidence.

---

## What makes it different

| Typical script folder | This harness |
| --- | --- |
| A few commands scattered in docs | A complete agent operating contract |
| Easy to run the wrong thing | Read/write/save gates are explicit |
| Assumes project structure | Discovers sessions and blocks from TIA |
| Generates XML from imagination | Starts from real exported TIA XML |
| Compile/save logic is ad hoc | Compile evidence unlocks guarded save |
| Hard to hand to another agent | Agent entry files and schemas are included |

---

## Good use cases

Use it when you want an agent to help with:

- LAD block inspection;
- LAD XML export and parsing;
- bounded LAD edits based on current project exports;
- global DB, UDT, and tag-table XML workflows;
- compile-gated import loops;
- project-side automation where evidence must be saved locally.

Do not use it for:

- online commissioning;
- forced values;
- PLC/HMI download;
- safety/F program edits;
- unsupported TIA versions without reviewing runtime/schema differences.

---

## Agent entrypoints

Start here:

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`
5. `schemas/action-plan.schema.json`
6. `templates/verified-template-catalog.json`

The short version for agents:

```text
Use the open TIA V18 project.
Export before editing.
Patch current evidence or reviewed templates only.
Write only with explicit approval.
Compile immediately.
Save only after clean guarded evidence.
Never download, go online, force variables, or touch safety/F blocks.
```

---

## Workspace policy

The `workspace/` folder is local runtime space:

```text
workspace/exports/
workspace/patched/
workspace/reports/
workspace/evidence/
```

These folders may contain real project XML, compile evidence, reports, logs, or project paths after use. They are ignored by `.gitignore` and should not be published unless intentionally sanitized.

---

## Star/download if this sounds familiar

- You want AI help inside industrial automation, but not uncontrolled automation.
- You need TIA Openness workflows that another agent can understand tomorrow.
- You prefer LAD deliverables because engineers can monitor them in TIA Portal.
- You care about compile evidence, project identity, and guarded save behavior.
- You want a portable harness instead of a one-off local script pile.

---

## License and trademark notice

MIT. See `LICENSE`.

This project is not affiliated with, endorsed by, or sponsored by Siemens. Siemens, TIA Portal, SIMATIC, and related names are trademarks of their respective owners.

This package does not include Siemens software or Siemens engineering libraries. Users must provide their own licensed TIA Portal V18 installation with Openness available.
