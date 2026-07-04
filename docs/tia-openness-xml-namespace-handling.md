# TIA Openness XML Namespace Handling

This note defines the namespace shape expected by this harness before importing
generated LAD/DB XML back into TIA Portal V18.

## Core Rule

Generated prefixes must be cleaned before import:

- no `ns0:` or `ns1:` element prefixes;
- no `flg:` or `if:` element prefixes;
- FlgNet elements use a default namespace on `<FlgNet>`;
- Interface sections use a default namespace on `<Sections>`;
- XML must still be well-formed after cleanup.

## TIA-Style Shapes

Interface sections use the Interface namespace as a default namespace:

```xml
<Interface>
  <Sections xmlns="http://www.siemens.com/automation/Openness/SW/Interface/v5">
    <Section Name="Static">
      <Member Name="StartCmd" Datatype="Bool" />
    </Section>
  </Sections>
</Interface>
```

LAD network source uses the FlgNet namespace as a default namespace:

```xml
<NetworkSource>
  <FlgNet xmlns="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v5">
    <Parts>
      <Access Scope="GlobalVariable" UId="21">...</Access>
      <Part Name="Contact" UId="24" />
    </Parts>
    <Wires>
      <Wire UId="28">
        <NameCon UId="24" Name="operand" />
      </Wire>
    </Wires>
  </FlgNet>
</NetworkSource>
```

## Why Cleanup Is Needed

XML serializers often turn namespaced elements into generated prefixes such as
`ns0:`, `ns1:`, `flg:`, or `if:`. Those prefixes can be well-formed XML but are
not the import shape this harness accepts for TIA V18 round trips.

## Harness Cleanup

Use the bundled cleaner instead of hand-written regex snippets:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Clean-LadXmlNamespace.ps1 `
  -XmlPath .\workspace\patched\generated.xml `
  -OutputPath .\workspace\patched\generated.clean.xml
```

The cleaner:

1. strips `ns0:`/`flg:` element prefixes and adds the FlgNet default namespace;
2. strips `ns1:`/`if:` element prefixes and adds the Interface default namespace to `Sections`;
3. removes prefixed namespace declarations left by generators;
4. removes unreferenced `Access` elements whose UId is not referenced by `IdentCon`;
5. validates the cleaned XML is well-formed;
6. prints a SHA256 hash for evidence.

## Verification Command

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-TiaV18LadHarness.ps1 `
  -Task ValidateXml `
  -XmlPath .\workspace\patched\generated.xml
```

For a direct text check:

```powershell
$text = Get-Content -Raw -Encoding UTF8 .\workspace\patched\generated.clean.xml
if ($text -match '</?(ns0|ns1|flg|if):') { throw "Generated namespace prefix remains" }
if ($text -notmatch '<FlgNet\b[^>]*xmlns=') { throw "FlgNet default namespace missing" }
[xml]$text | Out-Null
```

## Common Symptoms

| Problem | Likely symptom |
| --- | --- |
| `ns0:` / `ns1:` prefix remains | import reports unexpected or prefixed element |
| `flg:` / `if:` prefix remains | import reports prefix/namespace creation errors |
| `FlgNet` lacks default namespace | import or compile fails despite well-formed XML |
| unreferenced `Access` remains | compile/import reports UID reference not used |
