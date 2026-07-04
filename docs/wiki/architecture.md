# Harness Architecture

`tia-v18-lad-agent-portable` is a self-contained agent harness for Siemens TIA
Portal V18 LAD work. It is designed to be copied into a TIA project workspace so
Codex, Kilo, Roo, Claude, Gemini, Copilot, Aider, Continue, Devin, Cline, or
another agent can discover the same commands, safety gates, and editing rules.

## Main Parts

- Agent entry files: `AGENTS.md`, `README.md`, `SKILL.md`, and the tool-specific
  pointers under `.cursor`, `.kilo`, `.kilocode`, `.roo`, `.continue`,
  `.windsurf`, `.github`, `.devin`, and `.clinerules`.
- Wrapper scripts: `scripts/Invoke-TiaV18LadHarness.ps1`,
  `scripts/Test-HarnessLiveRoundTrip.ps1`,
  deferred `scripts/New-TiaV18DisposableLadProject.ps1` support, and validators.
- Bundled CLI: `tools/bin/AiPlcTiaV18.exe` plus
  `tools/bin/AiPlcTiaV18.Core.dll`. The CLI owns direct TIA Openness calls.
- Workspace: `workspace/exports`, `workspace/patched`, `workspace/reports`, and
  `workspace/evidence`.
- Docs and schemas: command reference, validation gates, editing contract, XML
  namespace handling, JSON schemas, examples, and this wiki.

## Data Flow

1. Probe TIA V18 and list open sessions.
2. Attach read-only to the chosen PID and summarize project/device/block state.
3. Export the current LAD block XML and parse it into an inspectable IR.
4. Edit the smallest XML scope possible against the exported base.
5. Validate XML and clean namespace prefixes when needed.
6. Import and compile only with `-AllowWrite` and project identity checks.
7. Save only after clean, fresh compile evidence from an import/compile write
   path.

## Write Boundaries

`-AllowCreate` only approves deferred disposable project creation under `%TEMP%`.
`-AllowWrite` is still required for import, compile, and save. `SaveProject`
requires clean evidence in `workspace/evidence/last-compile.json`.
