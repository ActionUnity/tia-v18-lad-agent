# Safety Gates

The harness separates discovery, edit preparation, import/compile, and save.
Agents must treat these as different risk levels.

## Read-Only Gate

Read-only commands are `Probe`, `ListSessions`, `AttachSummary`, `ListBlocks`,
`FindBlock`, `ExportBlock`, and `ParseLad`. These should be used before any
write command.

## Create Gate

`New-TiaV18DisposableLadProject.ps1` requires `-AllowCreate` and restricts
`-TargetRoot` to `%TEMP%`. It is only for disposable projects.

## Write Gate

`ImportXml`, `ImportCompile`, `CompilePlc`, `RoundTrip` with XML input, and
`SaveProject` require `-AllowWrite`. The wrapper removes stale compile evidence
before write attempts.

## Save Gate

`SaveProject` accepts only default workspace evidence from `ImportCompile` or
`RoundTripCompile`. The evidence must match PID/processId, be fresh, have
`exitCode=0`, `success=true`, and `errorCount=0`.

## Live Gate 3

Live Gate 3 for an existing project must start with an unchanged self-import of
the current export and compile. Use the approved `.ap18` path as an identity
lock, and do not save on the first proof:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block from discovery>" `
  -ExpectedProjectPath "<approved .ap18>" `
  -SelfImportExportedXml `
  -AllowWrite
```

Do not pass `-Save` for the first write proof.
