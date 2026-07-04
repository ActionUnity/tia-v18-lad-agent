# Copilot Instructions

This repository is a portable TIA Portal V18 LAD editing harness.

Before any PLC edit, read and follow:

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`
5. `schemas/action-plan.schema.json`

Hard gates:

- Deliver FB/FC logic as LAD unless the user explicitly asks otherwise.
- Export the current TIA V18 XML or use a verified template before writing XML.
- Do not invent free-form FlgNet XML.
- Import must be followed by compile.
- Import, standalone compile, and save tasks require explicit approval and `-AllowWrite`.
- Existing-project writes must include `-ExpectedProjectPath` or `-ExpectedProjectName`.
- First existing-project write proof is unchanged self-import of the current export; do not save until the save gate is explicitly approved.
- Save only through `scripts/Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -AllowWrite -ExpectedProjectPath <ap18>` after `ImportCompile`/`RoundTripCompile` evidence shows matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.
- Never download, go online, force variables, or edit safety/F blocks.

For live discovery, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -DiscoveryOnly
```

Then use a real LAD block name from discovery, not placeholder prose.
