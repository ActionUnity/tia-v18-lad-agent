# Roo Agent Entry

This is a short entrypoint shim. Before any PLC edit, read and follow:

1. `AGENTS.md` - primary autopilot contract and safety rules.
2. `harness.json` - command map, entrypoints, schemas, and workspace layout.
3. `docs/editing-contract.md` - allowed LAD XML edit tiers and validation workflow.
4. `docs/validation-gates.md` - required proof gates before claiming write success.

Hard gates:

- LAD-first: deliver FB/FC logic as LAD unless the user explicitly requests another final language.
- Use a real current TIA V18 export or a verified template/catalog entry before writing XML; do not invent free-form FlgNet XML.
- After import, compile immediately and inspect diagnostics.
- Import, standalone compile, and save tasks require explicit approval and `-AllowWrite`.
- Existing-project writes must include `-ExpectedProjectPath` or `-ExpectedProjectName`.
- If validating an already-open real project, do not create a new TIA project; first use an unchanged self-import, clean compile evidence, and no save until the save gate is explicitly approved.
- Disposable project creation is deferred/fallback support and requires separate `-AllowCreate`; later import/compile/save still require `-AllowWrite`.
- Save only through `Invoke-TiaV18LadHarness.ps1 -Task SaveProject -Pid <pid> -AllowWrite -ExpectedProjectPath <ap18>` after `ImportCompile`/`RoundTripCompile` evidence shows matching PID/processId, fresh `createdAt`, `exitCode=0`, `success=true`, and `errorCount=0`.
- Never download to PLC/HMI, go online, force variables, or edit safety/F blocks or F objects.

Safe loop:

`Probe -> ListSessions -> AttachSummary -> ExportBlock -> ParseLad -> patch exported XML or verified template -> CleanXml/ValidateXml -> ImportCompile with -AllowWrite -ExpectedProjectPath <ap18> -> read-back -> SaveProject -AllowWrite -ExpectedProjectPath <ap18> only after clean save-eligible evidence`

Report commands run, changed files, exported XML path and base hash, imported XML path, compile JSON summary, save status, and any manual TIA review still needed.
