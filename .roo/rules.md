# Roo Rules

This folder is a portable TIA Portal V18 LAD editing harness.

Use `AGENTS.md` as the primary contract and `harness.json` as the command map.
Use `docs/editing-contract.md` for allowed LAD XML edits and
`docs/validation-gates.md` for proof gates.

Do:

- start with `scripts\Test-HarnessOffline.ps1`;
- discover sessions and block paths instead of guessing;
- export current XML before patching;
- keep FB/FC delivery in LAD;
- import and compile before save;
- pass `-AllowWrite` only after explicit approval for the target PID/project/block;
- include `-ExpectedProjectPath` or `-ExpectedProjectName` on existing-project writes;
- use unchanged self-import of the current export for first existing-project write proof;
- treat import, standalone compile, and save as state-changing operations;
- save only via guarded `Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -AllowWrite -ExpectedProjectPath <ap18>` after `ImportCompile`/`RoundTripCompile` evidence shows matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.

Do not:

- download to PLC/HMI;
- go online;
- force variables;
- edit safety/F blocks;
- import free-form generated FlgNet XML without a real export or verified template base.

Live discovery entry:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 -DiscoveryOnly
```

Then use a real LAD block name from discovery, not placeholder prose.
