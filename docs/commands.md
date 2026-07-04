# Command Reference

Run commands from the portable harness folder:

```powershell
cd C:\Path\To\YourTiaProject\tia-v18-lad-agent
```

## Offline Validation

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1
```

## Environment And Session Discovery

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task Probe
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListSessions
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task AttachSummary -Pid <pid>
```

## Live Read Round Trip

Run discovery first. This does not import or save:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -DiscoveryOnly
```

Then copy a real LAD block name/path from `AttachSummary` or `ListBlocks`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name from discovery>"
```

Do not pass explanatory placeholder text as `-Query`.

## Existing Project No-Op Write Proof

Use this after explicit approval for the exact PID/project/block. It imports the
current export unchanged and compiles it, proving the write/compile chain without
making a logical change. The command must include `-ExpectedProjectPath` for the
approved `.ap18` and must not use parser fixtures as import seeds:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name from discovery>" `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -SelfImportExportedXml `
  -AllowWrite
```

For a reviewed patched XML:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual LAD block name from discovery>" `
  -PatchedXmlPath .\workspace\patched\<reviewed>.xml `
  -ExpectedProjectPath "<approved .ap18 path>" `
  -AllowWrite `
  -CleanXml
```

Do not pass `-Save` for first write validation.

## Deferred Disposable Project Support

When a separate disposable test project is explicitly allowed, create it with
the guarded prep script. It delegates TIA work to the bundled x64 C# CLI, writes
under `%TEMP%`, creates a real LAD FB, and never uses `examples/xml` parser
fixtures as import seeds. `-AllowCreate` does not approve later
import/compile/save operations; those still require `-AllowWrite` and project
identity checks.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-TiaV18DisposableLadProject.ps1 -AllowCreate
```

## List And Locate Blocks

Use this before export when the exact TIA block path is unknown:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid>
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ListBlocks -Pid <pid> -Query "<block name fragment>"
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task FindBlock -Pid <pid> -Query "<actual LAD block name>"
```

`FindBlock` returns `resolvedBlockPath`; use that value for deterministic export.

## Export LAD Block XML

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ExportBlock `
  -Pid <pid> `
  -BlockPath "<resolved block path>" `
  -OutDir .\workspace\exports
```

Query export is only for a real block name that discovery already showed as an
exact or unique match:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ExportBlock `
  -Pid <pid> `
  -Query "<actual LAD block name>" `
  -OutDir .\workspace\exports
```

## Parse LAD XML Offline

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ParseLad `
  -BlockPath "<resolved block path>" `
  -XmlPath .\workspace\exports\<exported>.xml
```

## Import XML

Import is a write operation. It requires explicit approval and `-AllowWrite`.
Use `-ExpectedProjectPath <approved .ap18>` or `-ExpectedProjectName <name>` on
every existing-project write command.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <xml> -Kind block -ExpectedProjectPath <ap18> -AllowWrite
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <xml> -Kind type -ExpectedProjectPath <ap18> -AllowWrite
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <xml> -Kind tag-table -ExpectedProjectPath <ap18> -AllowWrite
```

## Compile And Save

`ImportXml`, `ImportCompile`, standalone `CompilePlc`, and `SaveProject` are
state-changing operations. Agents must not run them without explicit approval
for the target project/PID/block, and the wrapper requires `-AllowWrite`.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task ImportCompile -Pid <pid> -XmlPath <xml> -Kind block -ExpectedProjectPath <ap18> -AllowWrite
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -ExpectedProjectPath <ap18> -AllowWrite

# Diagnostic compile only; requires -AllowWrite and does not unlock SaveProject.
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task CompilePlc -Pid <pid> -ExpectedProjectPath <ap18> -AllowWrite
```

`ImportCompile` imports and compiles in one attach session but does not save.
`ImportCompile` and the compile phase of live `RoundTrip` write save-eligible
evidence to `workspace/evidence/last-compile.json`. Standalone `CompilePlc` is
diagnostic-only and is not enough to unlock `SaveProject`.

`SaveProject` proceeds only when the evidence was produced by `ImportCompile` or
`RoundTripCompile`, belongs to the same PID/processId, has `createdAt` no older
than 30 minutes, and reports `exitCode: 0`, `success: true`, and
`errorCount: 0`.

Do not call `tools/bin/AiPlcTiaV18.exe save-project` directly from an agent. Use
the wrapper task above so the compile gate is enforced.

## Clean XML Namespace Prefixes

After Python-based LAD XML generation, remove namespace prefixes and unreferenced
`Access` elements:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task CleanXml `
  -XmlPath .\workspace\patched\patched-block.generated.xml `
  -OutputPath .\workspace\patched\patched-block.generated.clean.xml
```

Or use the script directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Clean-LadXmlNamespace.ps1 `
  -XmlPath .\input.xml `
  -PassThru
```

## ImportCompile With Namespace Cleaning

Use `-CleanXml` when importing generated XML that may contain `ns0:`/`ns1:`/
`if:`/`flg:` element prefixes.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ImportCompile `
  -Pid <pid> `
  -XmlPath .\workspace\patched\patched-block.generated.xml `
  -Kind block `
  -AllowWrite `
  -CleanXml
```

## Validate XML After Cleaning

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ValidateXml `
  -XmlPath .\workspace\patched\patched-block.generated.xml
```
