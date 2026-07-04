# LAD XML Editing Contract for TIA V18

This document defines what an agent may and may not do when editing LAD XML in this harness.

## Editing tiers

### Tier 1: Conservative patch (MVP)
Safe, bounded edits against an existing TIA-exported block:

| Operation | Allowed target | Required evidence | Risk |
| --- | --- | --- | --- |
| `renameNetwork` | `MultilingualText CompositionName="Title"` under one compile unit | base hash + network id/index | low |
| `editNetworkComment` | `MultilingualText CompositionName="Comment"` under one compile unit | base hash + network id/index | low |
| `replaceOperand` | `Access/Symbol/Component` chain for an existing operand | base hash + old/new symbol + DB/tag exists | medium |
| `insertNetworkFromVerifiedTemplate` | new compile unit copied from catalog template | template compile evidence + parameter validation | high |

### Tier 2: Generative edit (controlled project generators)
When an agent generates **new FlgNet networks** (not from the verified template catalog), the following admission conditions apply:

#### Entry gate
1. A project-specific Python generator exists for the current project, normally under `scripts/Generate-*.py` or in that project's own automation folder.
2. The generator is run **offline** (no TIA attach) and produces a patched XML.
3. The generator performs **namespace post-processing** (see `docs/tia-openness-xml-namespace-handling.md`) to strip `ns0:`/`ns1:` prefixes.
4. The generator performs **dangling Access cleanup**: any `Access` element whose UId is not referenced by at least one wire `IdentCon` is removed.
5. The generator validates **UID uniqueness** within each `FlgNet`.
6. The generated XML is parsed back as well-formed XML before import.

#### Verification steps
1. Diff generated XML against the original TIA export for structural integrity.
2. Verify no generated/python prefixes remain in the output: no `ns0:`, `ns1:`, `if:`, or `flg:` element prefixes.
3. Verify FlgNet and Interface sections use default `xmlns="..."` declarations, matching TIA exports.
4. Inspect compile-unit ID continuity (no duplicate `ID` attributes in the ObjectList).
5. After import, compile immediately and inspect diagnostics JSON.

#### Post-generation checks
```powershell
# 1. Check for ns0:/ns1: remnants (should return empty)
Select-String -Path <output.xml> -Pattern 'ns0:|ns1:' -SimpleMatch

# 2. Validate well-formed
[xml](Get-Content <output.xml> -Raw -Encoding UTF8) | Out-Null

# 3. Check UID duplicates (generator already validates, but spot-check)
python -c "
import xml.etree.ElementTree as ET
tree = ET.parse('<output.xml>')
# scan FlgNet elements
"
```

### Why LAD XML must be treated conservatively

TIA LAD export is SimaticML plus Siemens FlgNet network XML. It contains object IDs, UIds, multilingual text, network source, symbol accesses, wires, and instruction parts. A syntactically valid XML file can still fail TIA import or compile if IDs, wires, interfaces, or operand symbols are inconsistent.

Therefore agents must not invent arbitrary FlgNet networks. The safe base is always one of:

1. a real TIA V18 export from the target project; or
2. a verified template catalog entry with compile evidence for the local TIA major version; or
3. a controlled project generator that has passed the Tier-2 admission gate above.

## Allowed first-stage edits (Tier 1)

| Operation | Allowed target | Required evidence | Risk |
| --- | --- | --- | --- |
| `renameNetwork` | `MultilingualText CompositionName="Title"` under one compile unit | base hash + network id/index | low |
| `editNetworkComment` | `MultilingualText CompositionName="Comment"` under one compile unit | base hash + network id/index | low |
| `replaceOperand` | `Access/Symbol/Component` chain for an existing operand | base hash + old/new symbol + DB/tag exists | medium |
| `insertNetworkFromVerifiedTemplate` | new compile unit copied from catalog template | template compile evidence + parameter validation | high |

## Not allowed in MVP

- deleting networks from production blocks;
- changing safety/F blocks or safety DBs;
- changing block interfaces without updating every caller/instance DB;
- creating DB members implicitly because a LAD operand references them;
- changing hardware addresses without an explicit tag-table plan;
- changing optimized/non-optimized memory layout casually;
- saving after import when compile has errors.

## Required metadata per patch

Every patch operation must include:

```json
{
  "operation": "replaceOperand",
  "blockPath": "<resolved block path from discovery>",
  "baseHash": "sha256:<64 hex chars>",
  "target": { "operandSymbol": "<existing operand symbol from export>" },
  "value": {
    "oldSymbol": "<existing operand symbol from export>",
    "newSymbol": "<approved replacement symbol>"
  },
  "risk": "medium"
}
```

The `baseHash` must match the current exported file before writing a patched file.

## FB/FC LAD workflow

1. `AttachSummary` to discover block path.
2. `ExportBlock` to `workspace/exports`.
3. `ParseLad` to see network titles/comments/operands.
4. Prepare patch operation using `schemas/lad-patch-operation.schema.json`.
5. Write patched XML into `workspace/patched`.
6. Parse patched XML again if it is LAD.
7. Import and compile with `Invoke-TiaV18LadHarness.ps1 -Task ImportCompile -Kind block -AllowWrite`.
8. Read back with `AttachSummary` or another project-specific check.
9. Save only through `Invoke-TiaV18LadHarness.ps1 -Task SaveProject -AllowWrite`; the wrapper requires `ImportCompile`/`RoundTripCompile` evidence in `workspace/evidence/last-compile.json` with matching PID/processId, `exitCode=0`, `success=true`, and `errorCount=0`.

## DB workflow

DB changes must be explicit. Add or edit DB XML only when the action plan states:

- DB name and number;
- memory layout (`Standard` is preferred for HMI/absolute monitoring scenarios);
- member name;
- datatype;
- initial value;
- address expectation if HMI/absolute binding matters.

Global DB XML imports use:

```powershell
Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <db.xml> -Kind block -AllowWrite
```

## UDT workflow

UDT XML imports use:

```powershell
Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <udt.xml> -Kind type -AllowWrite
```

If a UDT changes shape, recompile every dependent block and DB.

## PLC tag table workflow

Tag tables must specify name, data type, and logical address. Imports use:

```powershell
Invoke-TiaV18LadHarness.ps1 -Task ImportXml -Pid <pid> -XmlPath <tags.xml> -Kind tag-table -AllowWrite
```

Never change real plant I/O addresses without explicit user approval.

## Compile diagnostics loop

After `ImportCompile`, inspect JSON:

- `success`
- `errorCount`
- `warningCount`
- `diagnostics[].state`
- `diagnostics[].description`
- `diagnostics[].path`

If `errorCount > 0`, do not save. Fix XML/source, re-import with `ImportCompile`, and recompile. Standalone `CompilePlc` is diagnostic-only for the guarded save flow; do not call raw `AiPlcTiaV18.exe save-project`.

## Python 生成后清理流水线

When Python-based LAD XML generators produce XML with `if:`/`flg:`/`ns0:`/`ns1:` element prefixes, the following cleaning pipeline is **mandatory** before TIA import:

### 1. Clean namespace prefixes

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Clean-LadXmlNamespace.ps1 `
  -XmlPath .\workspace\patched\generated.xml `
  -OutputPath .\workspace\patched\generated.clean.xml
```

This script:
- Replaces `ns0:`/`flg:` prefixes with default `xmlns="..."` (FlgNet namespace)
- Replaces `ns1:`/`if:` prefixes with default `xmlns="..."` on Interface sections
- Removes `xmlns:flg`, `xmlns:if`, `xmlns:ns0`, `xmlns:ns1` declarations
- Deletes unreferenced `Access` elements (UId not referenced by any `IdentCon`)
- Validates XML well-formedness
- Computes SHA256

### 2. Validate (optional standalone)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ValidateXml `
  -XmlPath .\workspace\patched\generated.clean.xml
```

### 3. Import with auto-clean

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ImportCompile `
  -Pid <pid> `
  -XmlPath .\workspace\patched\generated.xml `
  -Kind block `
  -AllowWrite `
  -CleanXml
```

### Why cleanup is required

TIA Openness import rejects:
- `ns0:FlgNet` / `ns1:Member` / `if:Member` / `flg:FlgNet` prefixes (Python ElementTree side effect)
- `xmlns:flg="..."` or `xmlns:if="..."` declarations on elements that should use default namespace
- Access elements with UIds never referenced by IdentCon ("The reference with the UID 'N' is defined but not used.")

Always run `Clean-LadXmlNamespace.ps1` or use `-CleanXml` before importing Python-generated LAD XML.
