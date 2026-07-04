# TIA V18 LAD Harness

Before editing Siemens TIA Portal PLC logic, read:

1. `AGENTS.md`
2. `harness.json`
3. `docs/editing-contract.md`
4. `docs/validation-gates.md`

Use wrapper commands in `scripts/`. Import, standalone compile, and save require
explicit approval and `-AllowWrite`. Existing-project writes must include
`-ExpectedProjectPath` or `-ExpectedProjectName`; first proof is unchanged
self-import of the current export, with no save until the save gate is
explicitly approved. Keep final FB/FC logic in LAD. Never download, go online,
force variables, or edit safety/F objects.
