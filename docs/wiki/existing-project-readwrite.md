# Existing Project Read/Write Validation

This page records the acceptance path for validating the harness against an
already-open real TIA V18 project without creating a new project.

## Target Lock

Always start by capturing:

- TIA PID from `ListSessions`
- exact `.ap18` path from `AttachSummary`
- target block path from `FindBlock` or `ListBlocks`

Every write command must include `-ExpectedProjectPath <ap18>` or
`-ExpectedProjectName <name>`.

## No-Op Write Proof

The lowest-risk write proof is an unchanged self-import:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<existing LAD block>" `
  -ExpectedProjectPath "<target .ap18>" `
  -SelfImportExportedXml `
  -AllowWrite `
  -Workspace "<external temp workspace>"
```

Use an external workspace such as `%TEMP%\tia-v18-lad-existing-project-readwrite-live`
so portable package validation remains clean.

## Save Proof

Save only after the no-op import/compile evidence is clean:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task SaveProject `
  -Pid <pid> `
  -ExpectedProjectPath "<target .ap18>" `
  -Workspace "<same external temp workspace>" `
  -AllowWrite
```

## Completion Evidence

Report the export hash, parse result, import hash, compile error/warning counts,
save result, and a post-save export/parse check.
