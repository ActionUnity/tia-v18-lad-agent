# TIA V18 LAD Harness

Before editing Siemens TIA Portal PLC logic, read `AGENTS.md`, `harness.json`,
`docs/editing-contract.md`, and `docs/validation-gates.md`.

Use wrapper commands in `scripts/`. Import, standalone compile, and save require
explicit approval and `-AllowWrite`. Existing-project writes must include
`-ExpectedProjectPath`. If validating an already-open real project, do not create
a new TIA project; first use unchanged self-import, clean compile evidence, and
no save until the save gate is explicitly approved. Disposable creation is
deferred/fallback support and requires separate `-AllowCreate`.
