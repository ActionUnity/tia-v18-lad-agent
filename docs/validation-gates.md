# Validation Gates

Use these gates before claiming this harness is ready for a target TIA V18
project. A green earlier gate does not imply a later gate passed.

Run these gates from the delivered `tia-v18-lad-agent-portable` folder or from
the top-level folder extracted from `tia-v18-lad-agent-portable.zip`. Do not
extract the zip directly over an existing project root. Do not use older harness
copies from a source tree as release evidence.

## Gate 1: Portable Package

Run after copying or extracting the harness:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

This proves the package has required entry files, runtime files, parseable
PowerShell/JSON/XML, a clean workspace, namespace-cleaner regression coverage,
and the expected CLI commands.

For release packaging, also run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessRelease.ps1 -ZipPath ..\tia-v18-lad-agent-portable.zip
```

This adds write-gate regression tests, live write-intent preflight checks,
installer portability checks, project-root agent pointer checks, and zip
structure/extraction validation. It still does not prove live TIA import.

## Gate 2: Live Read Round Trip

Open the target `.ap18` project in TIA Portal V18, then discover real block
names:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -DiscoveryOnly
```

Run read-only export/parse against a real LAD block discovered from the project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -Query "<actual LAD block name from discovery>"
```

This proves Openness attach, block discovery, LAD XML export, and LAD parsing.
It does not prove import or compile.

## Gate 3: Existing Project Write And Compile

Get explicit approval for the exact PID/project/block first. The first write
proof for an existing project is an unchanged self-import of the current export
followed by compile. It must include `-ExpectedProjectPath <approved .ap18>`,
use a real block from discovery, and must not save:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name>" `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -SelfImportExportedXml `
  -AllowWrite
```

For a reviewed patch, pass the reviewed XML explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name>" `
  -PatchedXmlPath .\workspace\patched\<reviewed>.xml `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -AllowWrite `
  -CleanXml
```

Do not pass `-Save` for first write validation. Inspect
`workspace/evidence/last-compile.json`; write validation is only proven when it
belongs to the same PID/processId, was produced by `ImportCompile` or
`RoundTripCompile`, has fresh `createdAt` no older than 30 minutes,
has `exitCode: 0`, and reports:

- `success: true`
- `errorCount: 0`

Only after that, and only with explicit save approval, use guarded save:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -ExpectedProjectPath "<approved .ap18 path>" -AllowWrite
```

## Deferred Disposable Project Support

Disposable project creation is fallback/deferred support only. If it is
explicitly allowed, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-TiaV18DisposableLadProject.ps1 -AllowCreate
```

It writes only under `%TEMP%`, does not import offline parser fixtures, and
`-AllowCreate` does not replace the later `-AllowWrite` gate. If automatic
startup fails, manually open a copied or disposable `.ap18` test project in TIA
Portal V18 and run the same no-op self-import proof against that visible session.
