---
name: tia-v18-lad-agent-harness
description: Use when an agent must edit Siemens TIA Portal V18 PLC objects with LAD as the delivered language through Openness export/import/compile. Provides exact commands, safety gates, schemas, and workflows for FB/FC LAD XML, Global DB, UDT, and PLC tag tables.
version: 0.2.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [tia-portal, openness, v18, lad, plc, harness]
    related_skills: []
---

# TIA V18 LAD Agent Harness

## Overview

This skill is a portable operating contract for a `tia-v18-lad-agent` folder. It keeps agents in a safe offline loop: export real TIA V18 XML, inspect/patch locally, import with Openness, compile, then save only through the guarded wrapper after compile success.

The user explicitly prefers LAD because it is easier to monitor in TIA Portal. Do not replace final FB/FC logic with SCL unless the user explicitly changes that requirement.

## When to Use

Use this harness when:

- editing FB/FC logic that must remain LAD;
- adding or changing Global DB/UDT/tag table objects that support LAD logic;
- round-tripping XML through TIA Openness V18;
- giving another agent enough context to operate without asking for tribal knowledge.

Do not use it for:

- online download, go-online monitoring, force tables, or safety/F block edits;
- free-form raw FlgNet generation without a real export/template base;
- TIA versions other than V18 without reviewing schema/runtime differences.

## Exact Commands

From the portable harness folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -Pid <pid> -DiscoveryOnly
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -Pid <pid> -Query "<actual block from discovery>"
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ExportBlock -Pid <pid> -BlockPath "<resolved block path>"
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ParseLad -BlockPath "<resolved block path>" -XmlPath <exported.xml>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task CleanXml -XmlPath <generated.xml> -OutputPath <cleaned.xml>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ValidateXml -XmlPath <xml>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <patched.xml> -Kind block -ExpectedProjectPath <ap18> -AllowWrite
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportCompile -Pid <pid> -XmlPath <xml> -Kind block -ExpectedProjectPath <ap18> -AllowWrite [-CleanXml]
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task CompilePlc -Pid <pid> -ExpectedProjectPath <ap18> -AllowWrite
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -ExpectedProjectPath <ap18> -AllowWrite
```

## Safe Editing Rules

1. Export first. Every write must be based on a current TIA export.
2. Record `sha256:<hash>` from export or `parse-lad`.
3. Patch only structured fields: network title/comment, operand symbol replacement, or verified-template insertion.
4. Keep DB/tag additions explicit; do not create variables implicitly because a LAD operand mentions them.
5. Validate XML well-formedness before import.
6. Import only after explicit approval for the target PID/project and with `-AllowWrite`; existing-project writes must include `-ExpectedProjectPath`. If validating an already-open real project, do not create a new TIA project; first use an unchanged self-import, clean compile evidence, and no save until the save gate is explicitly approved.
7. Do not call raw `AiPlcTiaV18.exe save-project`; the wrapper checks `workspace/evidence/last-compile.json` for `ImportCompile`/`RoundTripCompile` evidence with matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.

## Verification Checklist

- [ ] `Test-HarnessOffline.ps1` passed.
- [ ] TIA V18 Openness probe succeeded.
- [ ] `ListSessions` identified the correct open project PID.
- [ ] `AttachSummary` showed the target block path.
- [ ] Exported XML path and base hash are recorded.
- [ ] LAD parser output was reviewed.
- [ ] Patched XML is well-formed.
- [ ] User explicitly approved/confirmed the import/write target, and the import command includes `-ExpectedProjectPath` and `-AllowWrite`.
- [ ] Import completed.
- [ ] `ImportCompile` or live `RoundTrip` compile returned `success=true` and `errorCount=0`.
- [ ] Save was executed only by the guarded wrapper after `ImportCompile`/`RoundTripCompile` evidence showed matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.
