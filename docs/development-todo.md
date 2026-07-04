# Development TODO

This TODO is the working contract for making `tia-v18-lad-agent-portable` a
copyable harness that any capable coding agent can recognize and use to inspect,
edit, import, compile, and guard Siemens TIA Portal V18 LAD work.

## Current Iteration

- [x] Objective updated: do not create new TIA projects for final validation;
  validate the full read/write chain against an already open TIA V18 project.
- [x] Review existing portable package purpose and safety surface.
- [x] Keep write operations gated by `-AllowWrite`.
- [x] Add project identity locks with `-ExpectedProjectPath` and
  `-ExpectedProjectName` for import, compile, and save.
- [x] Guard `SaveProject` with fresh clean `ImportCompile` or
  `RoundTripCompile` evidence.
- [x] Add guarded disposable project creation entrypoint with `-AllowCreate`.
- [x] Move disposable project TIA Openness work out of PowerShell reflection and
  into the bundled x64 C# CLI.
- [x] Restrict disposable `-TargetRoot` to the current `%TEMP%` tree.
- [x] Add offline/release regression tests for `-AllowCreate`, non-TEMP target
  rejection, dangerous disposable names, and CLI help coverage.
- [x] Diagnose local V18 behavior: `CreateFB(LAD)` may be rejected with a
  ProDiag-only message on newly created catalog devices.
- [x] Add generated LAD XML fallback for disposable seed creation.
- [x] Align generated disposable LAD seed XML with V18 `FlgNet/v4` namespace.
- [x] Confirm the selected TIA session PID and exact `.ap18` path.
- [x] Export and parse an existing LAD block from the selected project.
- [x] Run a no-op self-import of the exported LAD XML back into the same project
  with `-AllowWrite` and `-ExpectedProjectPath`.
- [x] Compile the project after the no-op import and record clean evidence.
- [x] Save only through guarded `SaveProject` if the no-op import/compile
  evidence is clean and the target path still matches the selected `.ap18`.
- [x] Rebuild portable zip and validate extracted package.

## Deferred Disposable Project Support

These items remain useful for future disposable validation, but they are not the
current default acceptance path for an already-open project workflow.

- [x] Add guarded disposable project creation entrypoint with `-AllowCreate`.
- [x] Move disposable project TIA Openness work out of PowerShell reflection and
  into the bundled x64 C# CLI.
- [x] Restrict disposable `-TargetRoot` to the current `%TEMP%` tree.
- [x] Diagnose local V18 behavior: `CreateFB(LAD)` may be rejected with a
  ProDiag-only message on newly created catalog devices.
- [x] Add generated LAD XML fallback for disposable seed creation.
- [x] Align generated disposable LAD seed XML with V18 `FlgNet/v4` namespace.
- [ ] Prove disposable project creation returns a saved `.ap18` containing
  `FB_HarnessGate3` when disposable validation is allowed again.

## Wiki And Agent Surface

- [x] Add wiki overview for package architecture and data flow.
- [x] Add wiki page for agent onboarding and entry files.
- [x] Add wiki page for safety gates and live validation gates.
- [x] Add wiki page for TIA V18 Openness XML/version compatibility.
- [x] Add wiki page for no-new-project existing TIA project read/write proof.
- [x] Link wiki pages from `README.md`, `AGENTS.md`, and `harness.json`.
- [x] Ensure short agent entry files mention `-AllowCreate`, `-AllowWrite`,
  `-ExpectedProjectPath`, existing-project no-op proof, and deferred disposable
  support.

## Release Criteria

- [x] `code/AiPlcTiaV18/build.ps1 -Task Test` passes.
- [x] `scripts/Test-HarnessOffline.ps1` passes from the portable folder.
- [x] `scripts/Test-HarnessRelease.ps1 -SkipZip` passes.
- [x] `scripts/Test-HarnessRelease.ps1 -ZipPath ..\tia-v18-lad-agent-portable.zip`
  passes after rebuilding the zip.
- [x] Existing-project live read/write evidence exists: export, parse,
  unchanged self-import, compile with zero errors, guarded save, and post-save
  export/parse.
