# Agent Onboarding

Agents should start with `AGENTS.md` and `harness.json`. Short tool-specific
files point back to those documents so the same rules apply across agent
software.

## Required First Steps

1. Run offline validation.
2. Probe TIA V18.
3. List sessions and identify the intended PID.
4. Run `AttachSummary` before choosing a block.
5. Export before editing.

## Required Write Checks

- Any import, compile, or save must include `-AllowWrite`.
- Existing-project writes must include `-ExpectedProjectPath <ap18>` or
  `-ExpectedProjectName <name>`.
- First existing-project write proof must be an unchanged self-import of the
  current export with `-SelfImportExportedXml -AllowWrite`; do not save it.
- Do not save after a diagnostic-only `CompilePlc`.
- Do not use parser fixtures in `examples/xml` as import seeds.

## Deferred Disposable Gate

Create a disposable project only when that fallback is explicitly allowed:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\New-TiaV18DisposableLadProject.ps1 -AllowCreate
```

Then open or select the disposable project PID and run the same unchanged
self-import proof with `-ExpectedProjectPath`.
