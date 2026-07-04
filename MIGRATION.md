# Portable Migration Guide

This folder is the portable unit:

```text
tia-v18-lad-agent/
```

Do not copy only `scripts/`. Live TIA operations require the bundled CLI:

```text
tools/bin/AiPlcTiaV18.exe
tools/bin/AiPlcTiaV18.Core.dll
```

The release zip contains a top-level `tia-v18-lad-agent-portable/` directory.
Extract it into an empty staging folder, then install or copy the contained
folder. Do not extract the zip directly over an existing project root.

## Recommended Layout

```text
<new TIA project workdir>/
  project.ap18
  tia-v18-lad-agent/
```

## Install

From the source harness root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\New\TiaProjectWorkdir"
```

Replace an existing copy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-HarnessToProject.ps1 `
  -TargetRoot "D:\Your\New\TiaProjectWorkdir" `
  -Force
```

The installer resets transient workspace artifact folders by default. It keeps
the folder structure but skips old files under:

```text
workspace/exports/
workspace/patched/
workspace/reports/
workspace/evidence/
```

Use `-IncludeWorkspaceArtifacts` only when you intentionally want to migrate a
specific project's old exports, patches, reports, or evidence.

The installer creates lightweight project-root agent pointers when absent, so an
agent opened at the project root still learns to read `tia-v18-lad-agent/AGENTS.md`.
Existing pointer files are not overwritten unless `-ForceAgentPointers` is used.
Use `-SkipAgentPointers` for a fully isolated subdirectory install.

## Validate The Copy

```powershell
cd "D:\Your\New\TiaProjectWorkdir\tia-v18-lad-agent"
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

This is the package gate. It does not prove live TIA attach.

For a stronger copied-package release check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessRelease.ps1
```

## Live Read Gate

Open the target `.ap18` project in TIA Portal V18 and run discovery:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -DiscoveryOnly
```

Then use a real LAD block name/path from discovery:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name from discovery>"
```

Do not use placeholder prose as `-Query`.

## Write Gate

Import is a write operation. Use it only after explicit approval for the exact
PID/project/block. Existing-project writes must include the approved
`-ExpectedProjectPath` and should start with an unchanged self-import of the
current export; parser fixtures are parse-only and are not import seeds:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ImportCompile `
  -Pid <pid> `
  -XmlPath .\workspace\patched\your_block.xml `
  -Kind block `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -AllowWrite `
  -CleanXml
```

`ImportCompile` writes `workspace/evidence/last-compile.json`. Guarded
`SaveProject` is allowed only when that evidence comes from `ImportCompile` or
`RoundTripCompile`, matches the requested PID/processId, and reports
fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task SaveProject `
  -Pid <pid> `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -AllowWrite
```

## Safety Boundaries

- No PLC/HMI download.
- No go-online operation.
- No variable forcing.
- No safety/F block edits.
- No XML import without explicit approval.
- No save after compile failure.
- No raw `AiPlcTiaV18.exe save-project`; use the guarded wrapper.
- Do not claim success without import/compile/read-back evidence.
