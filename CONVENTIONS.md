# Aider Conventions

Before editing Siemens TIA Portal PLC logic, read and follow:

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`

Use wrapper commands in `scripts/`. Import, standalone compile, and save require
explicit approval and `-AllowWrite`. Existing-project writes must include
`-ExpectedProjectPath` or `-ExpectedProjectName`. If validating an already-open
real project, do not create a new TIA project; first use unchanged self-import,
clean compile evidence, and no save until the save gate is explicitly approved.
Disposable creation is deferred/fallback support and requires separate
`-AllowCreate`. Keep final FB/FC logic in LAD. Never download, go online, force
variables, or edit safety/F objects.
