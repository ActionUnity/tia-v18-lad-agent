# Kilo Code Rules

This folder is a portable TIA Portal V18 LAD editing harness.

Read these first:

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`
5. `schemas/action-plan.schema.json`

Required workflow:

`Probe -> ListSessions -> AttachSummary -> FindBlock/ListBlocks -> ExportBlock -> ParseLad -> patch current export or verified template -> ValidateXml/CleanXml -> ImportCompile -AllowWrite -ExpectedProjectPath <ap18> -> guarded SaveProject -AllowWrite -ExpectedProjectPath <ap18> only after clean save-eligible evidence`

Safety rules:

- Keep delivered FB/FC logic in LAD.
- Do not invent raw FlgNet XML.
- Import, standalone compile, and save tasks require explicit approval and `-AllowWrite`.
- Existing-project writes must include `-ExpectedProjectPath` or `-ExpectedProjectName`; first proof is unchanged self-import of the current export.
- Do not save without `ImportCompile`/`RoundTripCompile` evidence in `workspace/evidence/last-compile.json` showing matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.
- Never download, go online, force variables, or edit safety/F blocks.

Live discovery entry:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -DiscoveryOnly
```

Then use a real LAD block name from discovery, not placeholder prose.
