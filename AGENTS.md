<!-- markdownlint-disable MD013 -->

# AGENTS.md - TIA V18 LAD Autopilot Contract

## Primary Design Intent

Before any PLC edit, read this file together with `harness.json`,
`docs/editing-contract.md`, and `docs/validation-gates.md`. Those files define
the command map, allowed LAD XML edit tiers, and proof gates.

This harness is not meant to make the human operate low-level commands. The
human should only need to:

1. Open the target `.ap18` project in TIA Portal V18.
2. Tell the agent in natural language what to change, for example:
   `Modify FB_MotorControl and add an emergency-stop reset LAD network.`

The agent must then automatically handle session discovery, block discovery,
export, LAD XML edit, import, compile, diagnostics, and optional guarded save.

## Autopilot Behaviour

When a user asks to modify PLC logic:

1. Run `Probe` to verify TIA V18 Openness.
2. Run `ListSessions`.
   - If exactly one session is found, use it automatically.
   - If zero sessions are found, ask the user only to open the TIA V18 project.
   - If multiple sessions are found, ask which project/session to use.
3. Run `AttachSummary` or equivalent discovery. Do not guess block paths.
4. Resolve the block from the user's natural-language request.
   - If the block name is exact, continue.
   - If ambiguous, ask one focused clarification.
5. Export the target block before editing.
6. Edit only the exported current XML or a verified template.
7. Keep final FB/FC logic in LAD unless the user explicitly asks for another language.
8. Import modified XML only after explicit approval for the exact target
   project/block and only with `-AllowWrite`. Existing-project write
   validation must start with an unchanged self-import of the current export,
   include `-ExpectedProjectPath <approved .ap18>`, and omit save on the first
   proof.
9. Compile immediately after import.
10. Iterate from diagnostics if compile fails.
11. Save only through `Invoke-TiaV18LadHarness.ps1 -Task SaveProject -AllowWrite`
    after an import/compile write step succeeds and the requested scope is
    satisfied. The wrapper checks `workspace/evidence/last-compile.json` for
    `sourceTask` `ImportCompile` or `RoundTripCompile`, matching `tiaPid` and
    `processId`, fresh `createdAt`, `exitCode=0`, `success=true`, and
    `errorCount=0`.

## Do Not Expose Harness Complexity

Do not tell the user to manually run `Probe`, copy PID, export XML, import XML,
or compile unless the current agent runtime lacks tool access. In normal
operation, those are internal implementation details.

## User-Facing Promise

The intended experience is:

```text
User: Modify FB_ServoControl and add an emergency-stop reset LAD network.
Agent: I will connect to the currently open TIA project, locate that FB, export it, patch the LAD XML, import it, and compile it.
```

Then the agent actually runs the tools and returns the result.

## Non-Negotiable Safety Rules

- Delivered FB/FC logic is LAD. Do not silently switch final logic to SCL.
- Never download to PLC/HMI, go online, force variables, or modify safety/F objects.
- Never import XML generated from free-form text without a real TIA export base
  or a verified template catalog entry.
- Never save a project after import unless compile returned zero errors.
- Never claim success from file timestamps or process exit alone. Show command,
  stdout/stderr, exit code, compile/read-back evidence, and save status.

## Required Action Plan Shape

Use `schemas/action-plan.schema.json`. At minimum:

```json
{
  "tiaVersion": "V18",
  "mode": "lad-offline-edit",
  "project": { "tiaProcessId": 12345, "plcSoftware": "first-plc" },
  "safety": {
    "offlineOnly": true,
    "downloadToDevice": false,
    "goOnline": false,
    "requiresCompileBeforeSave": true,
    "requiresBackupBeforeWrite": true
  },
  "operations": []
}
```

## Safe Write Loop

Before claiming success for a target project, apply the gates in
`docs/validation-gates.md`. Read-only export/parse success is not write success.
When validating an already-open target project, do not create a new TIA project;
use the target PID, `-ExpectedProjectPath`, an unchanged self-import, clean
compile evidence, and no save until the save gate is explicitly approved.
Disposable project creation is deferred/fallback support only:
`scripts/New-TiaV18DisposableLadProject.ps1 -AllowCreate` may be used only for a
separate disposable test project. It delegates TIA work to the bundled x64 C#
CLI, writes under `%TEMP%`, and never makes parser fixtures import seeds.
`-AllowCreate` does not replace the later `-AllowWrite` gate.

```text
Probe -> ListSessions -> AttachSummary
ExportBlock / export DB/tag XML
ParseLad / inspect XML
Prepare patch against current baseHash
CleanXml if generated XML may contain ns0:/ns1:/if:/flg: prefixes
ValidateXml
ImportCompile -AllowWrite -ExpectedProjectPath <approved .ap18 path>
AttachSummary/read-back
SaveProject -AllowWrite -ExpectedProjectPath <approved .ap18 path> only after save-eligible evidence is clean
```

See `docs/wiki/architecture.md`, `docs/wiki/agent-onboarding.md`,
`docs/wiki/safety-gates.md`, `docs/wiki/tia-v18-xml-compatibility.md`,
`docs/wiki/existing-project-readwrite.md`, and `docs/development-todo.md` for
the package wiki and current TODO.

`ImportCompile` and the compile phase of `RoundTrip` write save-eligible compile
evidence to `workspace/evidence/last-compile.json`. Standalone `CompilePlc` is
diagnostic-only and does not unlock `SaveProject`. `SaveProject` refuses when
evidence is missing, belongs to another PID/processId, was not produced by
`ImportCompile` or `RoundTripCompile`, is older than 30 minutes, or has `exitCode != 0`,
`success != true`, or `errorCount != 0`.

For first contact with a real TIA V18 project, prefer the live validator:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessLiveRoundTrip.ps1 `
  -Pid <pid> `
  -Query "<actual block name from AttachSummary/ListBlocks>"
```

It performs discovery, export, parse, optional import-compile, optional guarded
save, and writes a report under `workspace/reports`. Do not pass placeholder
prose as `-Query`; use a real block path/name discovered from the open TIA
project.

## Working With Generated LAD XML

When project-specific generators produce LAD XML, the output can contain
`if:`/`flg:`/`ns0:`/`ns1:` namespace prefixes that TIA Openness cannot import
directly. Always run the namespace cleaner before import:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task CleanXml `
  -XmlPath .\workspace\patched\generated.xml `
  -OutputPath .\workspace\patched\generated.clean.xml
```

Or use `-CleanXml` with `ImportCompile`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ImportCompile `
  -Pid <pid> `
  -XmlPath .\workspace\patched\generated.xml `
  -Kind block `
  -AllowWrite `
  -CleanXml
```

## Block Path Handling

Do not guess block paths. Use `AttachSummary`, `ListBlocks`, or `FindBlock` to
discover the actual path. Examples may look like:

```text
Program blocks/<actual block name>
Program blocks/<folder>/<actual block name>
```

Use exactly what the tool reports.

## What To Return To The User

Always include:

- commands run;
- files changed;
- exported XML path and base hash when available;
- imported XML path;
- compile result JSON summary;
- read-back evidence;
- whether save was executed;
- anything that still needs manual TIA review.
