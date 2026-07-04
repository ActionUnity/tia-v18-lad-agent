# TIA V18 XML Compatibility

TIA Openness XML is version-sensitive. Agents should prefer current exports from
the target project over handwritten XML.

## Namespaces

Local TIA V18 LAD exports in this workspace use:

```xml
http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v4
```

Some external samples use `FlgNet/v5`. Those may parse offline but fail to
import into this V18 project context. Use `Clean-LadXmlNamespace.ps1` and current
exports as the source of truth.

## Existing Export Seed

For existing-project validation, the only seed for no-op self-import is the XML
exported from the same project and target block in the current session.

## Deferred Disposable Seed

The disposable project command first attempts TIA-native `CreateFB(..., LAD)`.
If the local catalog rejects that path, it imports an internally generated,
minimal V18 LAD FB XML seed. This seed is not the parser fixture under
`examples/xml`; it exists only to create a real disposable block when disposable
validation is explicitly allowed.

## Parser Fixtures

`examples/xml` files are for parser and cleaner regression tests. They are not
validated import seeds for an existing project.
