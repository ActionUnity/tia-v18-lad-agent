# Workspace

This directory is generated/used by the harness runner.

Expected subdirectories:

```text
workspace/
  exports/   # XML exported from current TIA project
  patched/   # reviewed XML ready to import
  reports/   # parse/compile/action-plan outputs
  evidence/  # screenshots, compile logs, manual review notes
```

Create it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 -Task PrepareWorkspace
```

Do not commit production project exports unless the user explicitly wants them versioned.
