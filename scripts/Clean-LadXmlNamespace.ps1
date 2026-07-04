param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [Alias("InputPath")]
    [string]$XmlPath,

    [Alias("OutFile", "Output")]
    [string]$OutputPath = "",

    [switch]$PassThru
)

<#
.SYNOPSIS
Cleans TIA V18 LAD XML: normalizes generated namespace prefixes,
converts FlgNet and Interface sections to default xmlns form,
removes unreferenced Access elements, and recomputes SHA256.

.DESCRIPTION
Use this after Python-based LAD XML generation
to produce TIA Openness-compatible XML. The script:

1. Fixes namespace declarations (ns0 → flg default, ns1 → if)
2. Strips FlgNet ns0:/flg: prefixes and Interface ns1:/if: prefixes
3. Removes Access elements whose UId is not referenced by any IdentCon
4. Computes SHA256 of the output file

.PARAMETER XmlPath
Path to the input LAD XML file (may contain ns0:/ns1:/if:/flg: prefixes).

.PARAMETER OutputPath
Path where the cleaned XML will be written. If omitted, writes to <XmlPath>.cleaned.xml.

.PARAMETER PassThru
Output the cleaned XML to stdout instead of writing to a file.
#>

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $XmlPath)) {
    throw "XML file not found: $XmlPath"
}

$xml = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8

$DefaultFlgNetNamespace = "http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v4"
$DefaultInterfaceNamespace = "http://www.siemens.com/automation/Openness/SW/Interface/v5"
$FlgNetNamespacePattern = "http://www\.siemens\.com/automation/Openness/SW/NetworkSource/FlgNet/v\d+"
$InterfaceNamespacePattern = "http://www\.siemens\.com/automation/Openness/SW/Interface/v\d+"

function Get-FirstNamespace {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Fallback
    )

    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return $Fallback
}

function Convert-PrefixedElementTags {
    param([string]$Text)

    $pattern = '<(?<Slash>/?)((?<Prefix>ns0|flg|ns1|if):)(?<Local>[A-Za-z_][A-Za-z0-9_.-]*)(?=[\s>/])'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)

        $slash = $match.Groups["Slash"].Value
        $prefix = $match.Groups["Prefix"].Value
        $local = $match.Groups["Local"].Value

        return ('<{0}{1}' -f $slash, $local)
    }

    return [regex]::Replace($Text, $pattern, $evaluator)
}

function Ensure-FlgNetDefaultNamespace {
    param(
        [string]$Text,
        [string]$Namespace
    )

    $regex = [regex]::new('<FlgNet(?=[\s>/])(?<Attrs>[^<>]*?)(?<Self>/?)>')
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)

        $attrs = $match.Groups["Attrs"].Value
        $self = $match.Groups["Self"].Value
        if ($attrs -match '(^|\s)xmlns=') {
            return $match.Value
        }

        return ('<FlgNet xmlns="{0}"{1}{2}>' -f $Namespace, $attrs, $self)
    }

    return $regex.Replace($Text, $evaluator)
}

function Ensure-InterfaceDefaultNamespace {
    param(
        [string]$Text,
        [string]$Namespace
    )

    $regex = [regex]::new('<Sections(?=[\s>/])(?<Attrs>[^<>]*?)(?<Self>/?)>')
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$match)

        $attrs = $match.Groups["Attrs"].Value
        $self = $match.Groups["Self"].Value
        if ($attrs -match '(^|\s)xmlns=') {
            return $match.Value
        }

        return ('<Sections xmlns="{0}"{1}{2}>' -f $Namespace, $attrs, $self)
    }

    $Text = $regex.Replace($Text, $evaluator)

    if ($Text -notmatch '<Sections(?=[\s>/])') {
        $interfaceRegex = [regex]::new('<Interface(?=[\s>/])(?<Attrs>[^<>]*?)(?<Self>/?)>')
        $interfaceEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param([System.Text.RegularExpressions.Match]$match)

            $attrs = $match.Groups["Attrs"].Value
            $self = $match.Groups["Self"].Value
            if ($attrs -match '(^|\s)xmlns=') {
                return $match.Value
            }

            return ('<Interface xmlns="{0}"{1}{2}>' -f $Namespace, $attrs, $self)
        }
        $Text = $interfaceRegex.Replace($Text, $interfaceEvaluator)
    }

    return $Text
}

$flgNamespace = Get-FirstNamespace `
    -Text $xml `
    -Pattern ('xmlns(?::(?:ns0|flg))?="(' + $FlgNetNamespacePattern + ')"') `
    -Fallback $DefaultFlgNetNamespace
$interfaceNamespace = Get-FirstNamespace `
    -Text $xml `
    -Pattern ('xmlns(?::(?:ns1|if))?="(' + $InterfaceNamespacePattern + ')"') `
    -Fallback $DefaultInterfaceNamespace

# ---- Step 1: Fix namespace declarations ----
# Prefixed FlgNet declarations are moved onto cleaned FlgNet tags as default xmlns.
$xml = $xml -replace ('\s+xmlns:(?:ns0|flg)="(' + $FlgNetNamespacePattern + ')"'), ''
# Prefixed Interface declarations are moved onto cleaned Sections/Interface tags as default xmlns.
$xml = $xml -replace ('\s+xmlns:(?:ns1|if)="(' + $InterfaceNamespacePattern + ')"'), ''

# ---- Step 2: Normalize generated element prefixes ----
# Match full element names so open, close, and self-closing tags keep their shape.

# Replace ns0: prefix on element tags → no prefix (uses default xmlns)
$xml = Convert-PrefixedElementTags -Text $xml
$xml = Ensure-FlgNetDefaultNamespace -Text $xml -Namespace $flgNamespace
$xml = Ensure-InterfaceDefaultNamespace -Text $xml -Namespace $interfaceNamespace

# Handle edge case: self-closing tags with prefixes

# ---- Step 3: Remove unreferenced Access elements ----
# Find all UIds in Access elements
$accessPattern = '<Access\s+Scope="[^"]*"\s+UId="(\d+)"[^>]*>'
$allAccessUIds = [regex]::Matches($xml, $accessPattern) | ForEach-Object { $_.Groups[1].Value }

# Find all UIds referenced by IdentCon elements
$identConPattern = '<IdentCon\s+[^>]*UId="(\d+)"[^>]*>'
$referencedUIds = [regex]::Matches($xml, $identConPattern) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
$refHash = @{}
foreach ($uid in $referencedUIds) {
    $refHash[$uid] = $true
}

# Remove unreferenced Access blocks
$unreferencedCount = 0
foreach ($uid in $allAccessUIds) {
    if (-not $refHash.ContainsKey($uid)) {
        # Remove the entire Access element (multi-line, from <Access to </Access>)
        $pattern = '<Access\s+[^>]*UId="' + $uid + '"[^>]*>.*?</Access>'
        $before = $xml.Length
        $xml = $xml -replace $pattern, ''
        if ($xml.Length -ne $before) {
            $unreferencedCount++
        }
    }
}

# ---- Step 4: Fix any remaining xmlns:flg / xmlns:if that got orphaned ----
# Remove orphaned xmlns declarations (empty attribute after removal)
$xml = $xml -replace '\s+xmlns:flg=""', ''
$xml = $xml -replace '\s+xmlns:if=""', ''
$xml = $xml -replace '\s+xmlns:ns0="[^"]*"', ''
$xml = $xml -replace '\s+xmlns:ns1="[^"]*"', ''
$xml = $xml -replace '\s+xmlns:if="[^"]*"', ''

# ---- Step 5: Ensure XML declaration present ----
if ($xml -notmatch '^\s*<\?xml') {
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' + "`r`n" + $xml
}

# ---- Step 6: Validate well-formedness ----
try {
    [xml]$xml | Out-Null
} catch {
    throw "Cleaned XML is not well-formed: $($_.Exception.Message)"
}

# ---- Step 7: Compute SHA256 ----
$utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($xml)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($utf8Bytes)
$hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

# ---- Step 8: Output ----
if ($PassThru) {
    Write-Output $xml
} else {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [System.IO.Path]::ChangeExtension($XmlPath, '.cleaned.xml')
    }
    $parentDir = Split-Path -Parent $OutputPath
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    [System.IO.File]::WriteAllText($OutputPath, $xml, [System.Text.Encoding]::UTF8)
}

# ---- Step 9: Report ----
Write-Host "=== Clean-LadXmlNamespace ==="
Write-Host "Input:  $XmlPath"
if (-not $PassThru) {
    Write-Host "Output: $OutputPath"
}
Write-Host "SHA256: $hashHex"
Write-Host "Unreferenced Access removed: $unreferencedCount"
Write-Host "Status: OK"
