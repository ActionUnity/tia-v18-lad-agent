param(
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $HarnessRoot)
$PortableExe = Join-Path $HarnessRoot "tools\bin\AiPlcTiaV18.exe"
$ProjectExe = Join-Path $ProjectRoot "artifacts\bin\AiPlcTiaV18.exe"

function Get-HarnessPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "Harness path is empty."
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $RelativePath
    }

    $normalized = $RelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
    return Join-Path $HarnessRoot $normalized
}

function Assert-HarnessFileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [string]$Description = "required harness file"
    )

    $path = Get-HarnessPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing ${Description}: $RelativePath"
    }
    return $path
}

function Assert-HarnessUtf8Readable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $path = Assert-HarnessFileExists -RelativePath $RelativePath -Description "UTF-8 readable file"
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [System.IO.File]::ReadAllText($path, $encoding) | Out-Null
    } catch {
        throw "File is not readable as strict UTF-8: $RelativePath. $($_.Exception.Message)"
    }
}

function Get-HarnessCliCommandName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandSpec
    )

    if ($CommandSpec -notmatch '^\s*(?:\.?[\\/])?AiPlcTiaV18\.exe\s+(.+)$') {
        return $null
    }

    return (($Matches[1] -split '\s+')[0])
}

Write-Host "Harness root: $HarnessRoot"
Write-Host "Project root candidate: $ProjectRoot"
Write-Host "Portable CLI candidate: $PortableExe"

$required = @(
    "README.md",
    "AGENTS.md",
    "SKILL.md",
    "harness.json",
    "schemas\action-plan.schema.json",
    "schemas\lad-patch-operation.schema.json",
    "scripts\Invoke-TiaV18LadHarness.ps1"
)
foreach ($relative in $required) {
    Assert-HarnessFileExists -RelativePath $relative | Out-Null
}

$HarnessConfigPath = Assert-HarnessFileExists -RelativePath "harness.json"
$HarnessConfig = Get-Content -LiteralPath $HarnessConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Checking agent entry files..."
$agentEntryFiles = @(
    "README.md",
    "AGENTS.md",
    "SKILL.md",
    "harness.json",
    "docs\editing-contract.md",
    "schemas\action-plan.schema.json",
    "templates\verified-template-catalog.json",
    "scripts\Invoke-TiaV18LadHarness.ps1",
    "scripts\Test-HarnessOffline.ps1"
)
foreach ($relative in $agentEntryFiles) {
    Assert-HarnessFileExists -RelativePath $relative -Description "agent entry file" | Out-Null
}

Write-Host "Checking README and AGENTS.md UTF-8 readability..."
Assert-HarnessUtf8Readable -RelativePath "README.md"
Assert-HarnessUtf8Readable -RelativePath "AGENTS.md"

Write-Host "Checking documentation for common mojibake markers..."
$textFiles = Get-ChildItem -LiteralPath $HarnessRoot -Recurse -Force -File |
    Where-Object {
        $_.Extension -in @(".md", ".json", ".ps1", ".mdc") -or
        $_.Name -in @(".cursorrules", ".windsurfrules", ".roorules")
    }
$mojibakeMarkers = @(
    [char]0x9367,
    [char]0x9422,
    [char]0x7ECB,
    [char]0x4E63,
    [char]0x4FD9,
    [char]0x9225,
    [char]0xFFFD,
    [char]0x00C3,
    [char]0x00C2,
    [char]0x951F,
    [char]0x935A,
    [char]0x59E9,
    [char]0x6DC7
)
$mojibakePattern = (($mojibakeMarkers | ForEach-Object { [regex]::Escape([string]$_) }) -join "|")
foreach ($file in $textFiles) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($text -match $mojibakePattern) {
        $relative = $file.FullName.Substring($HarnessRoot.Length + 1)
        throw "Documentation appears to contain mojibake markers: $relative"
    }
}

Write-Host "Checking harness.json entrypoints..."
if (-not $HarnessConfig.entrypoints) {
    throw "harness.json is missing entrypoints."
}
foreach ($entrypoint in $HarnessConfig.entrypoints.PSObject.Properties) {
    Assert-HarnessFileExists -RelativePath ([string]$entrypoint.Value) -Description "harness.json entrypoint '$($entrypoint.Name)'" | Out-Null
}

Write-Host "Checking required runtime files..."
if (-not $HarnessConfig.requiredRuntimeFiles -or $HarnessConfig.requiredRuntimeFiles.Count -eq 0) {
    throw "harness.json is missing requiredRuntimeFiles."
}
foreach ($relative in $HarnessConfig.requiredRuntimeFiles) {
    Assert-HarnessFileExists -RelativePath ([string]$relative) -Description "required runtime file" | Out-Null
}

Write-Host "Checking workspace is free of project artifacts..."
$workspaceRoot = Join-Path $HarnessRoot "workspace"
if (Test-Path -LiteralPath $workspaceRoot) {
    $allowedWorkspacePlaceholders = @("README.md", ".gitkeep")
    $projectArtifacts = Get-ChildItem -LiteralPath $workspaceRoot -File -Force -Recurse |
        Where-Object { $allowedWorkspacePlaceholders -notcontains $_.Name }
    if ($projectArtifacts.Count -gt 0) {
        $relativeArtifacts = $projectArtifacts | ForEach-Object {
            $_.FullName.Substring($HarnessRoot.Length + 1)
        }
        throw "Workspace contains non-README project artifacts: $($relativeArtifacts -join ', ')"
    }
}

Write-Host "Parsing PowerShell scripts..."
$psFiles = Get-ChildItem -Path (Join-Path $HarnessRoot "scripts") -Filter *.ps1 -Recurse
foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $joined = ($errors | ForEach-Object { $_.Message }) -join "; "
        throw "PowerShell parse error in $($file.FullName): $joined"
    }
}

Write-Host "Parsing JSON files..."
$jsonFiles = Get-ChildItem -Path $HarnessRoot -Filter *.json -Recurse
foreach ($file in $jsonFiles) {
    Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
}

Write-Host "Parsing XML examples..."
$xmlRoot = Join-Path $HarnessRoot "examples\xml"
if (Test-Path -LiteralPath $xmlRoot) {
    $xmlFiles = Get-ChildItem -Path $xmlRoot -Filter *.xml -Recurse
    foreach ($file in $xmlFiles) {
        [xml](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) | Out-Null
    }
}

Write-Host "Checking XML namespace cleaner regression..."
$tempBase = [System.IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("tia-lad-cleaner-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $fixturePath = Join-Path $tempRoot "namespace-prefix.fixture.xml"
    $cleanedPath = Join-Path $tempRoot "namespace-prefix.cleaned.xml"
    $fixtureXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<Document xmlns:flg="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v4" xmlns:ns0="http://www.siemens.com/automation/Openness/SW/NetworkSource/FlgNet/v4" xmlns:if="http://www.siemens.com/automation/Openness/SW/Interface/v5" xmlns:ns1="http://www.siemens.com/automation/Openness/SW/Interface/v5">
  <flg:FlgNet>
    <flg:Parts />
  </flg:FlgNet>
  <ns0:FlgNet>
    <ns0:Wires />
  </ns0:FlgNet>
  <flg:FlgNet />
  <ns0:FlgNet />
  <if:Interface>
    <if:Sections />
  </if:Interface>
  <ns1:Interface>
    <ns1:Sections />
  </ns1:Interface>
  <if:Interface />
  <ns1:Interface />
</Document>
'@
    [System.IO.File]::WriteAllText($fixturePath, $fixtureXml, [System.Text.Encoding]::UTF8)

    & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot "Clean-LadXmlNamespace.ps1") -XmlPath $fixturePath -OutputPath $cleanedPath
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $cleaned = Get-Content -LiteralPath $cleanedPath -Raw -Encoding UTF8
    [xml]$cleaned | Out-Null
    if ($cleaned -match '</?(?:flg|ns0|ns1|if):') {
        throw "Namespace cleaner left forbidden element prefixes in regression fixture."
    }
    if ($cleaned -notmatch '<FlgNet\b[^>]*>' -or $cleaned -notmatch '</FlgNet>' -or $cleaned -notmatch '<FlgNet\b[^>]*/>') {
        throw "Namespace cleaner did not preserve FlgNet open/close/self-closing tag shapes."
    }
    if ($cleaned -notmatch '<Interface\b[^>]*>' -or $cleaned -notmatch '</Interface>' -or $cleaned -notmatch '<Interface\b[^>]*/>') {
        throw "Namespace cleaner did not preserve Interface open/close/self-closing tag shapes."
    }
    if ($cleaned -notmatch '<Sections\b[^>]*xmlns="http://www\.siemens\.com/automation/Openness/SW/Interface/v5"') {
        throw "Namespace cleaner did not place the Interface namespace on Sections."
    }
} finally {
    $tempBaseFullPath = [System.IO.Path]::GetFullPath($tempBase)
    $tempRootFullPath = [System.IO.Path]::GetFullPath($tempRoot)
    if ($tempRootFullPath.StartsWith($tempBaseFullPath, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if (-not $SkipBuild) {
    $Exe = $null

    if (Test-Path -LiteralPath $PortableExe) {
        Write-Host "Using portable CLI bundled in harness."
        $Exe = $PortableExe
    } elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot "build.ps1")) {
        Write-Host "Running project build + offline tests from source tree..."
        & powershell -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot "build.ps1") -Task Test
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
        if (Test-Path -LiteralPath $ProjectExe) {
            $Exe = $ProjectExe
        }
    }

    if (-not $Exe) {
        throw "AiPlcTiaV18.exe not found. Portable harness requires tools\bin\AiPlcTiaV18.exe and AiPlcTiaV18.Core.dll."
    }

    Write-Host "Checking harness commands in CLI help..."
    $helpOutput = & $Exe --help 2>&1
    $helpText = ($helpOutput | Out-String)
    $helpCommands = @()
    try {
        $helpJson = $helpText | ConvertFrom-Json
        if ($helpJson.commands) {
            $helpCommands = @($helpJson.commands | ForEach-Object { (($_ -split '\s+')[0]) })
        }
    } catch {
        $helpCommands = @()
    }

    if (-not $HarnessConfig.commands) {
        throw "harness.json is missing commands."
    }
    $expectedCliCommands = @(
        "probe-env",
        "list-sessions",
        "attach-summary",
        "list-blocks",
        "find-block",
        "export-block",
        "parse-lad",
        "import-xml",
        "import-compile",
        "compile-plc",
        "save-project",
        "create-disposable-lad-project"
    )
    $harnessCommands = @(
        $HarnessConfig.commands.PSObject.Properties |
            ForEach-Object { Get-HarnessCliCommandName -CommandSpec ([string]$_.Value) } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
    $harnessCommands = @($harnessCommands + $expectedCliCommands | Select-Object -Unique)
    $missing = @()
    foreach ($cmd in $harnessCommands) {
        if ($helpCommands.Count -gt 0) {
            if ($helpCommands -notcontains $cmd) {
                $missing += $cmd
            }
        } elseif ($helpText -notmatch [regex]::Escape($cmd)) {
            $missing += $cmd
        }
    }
    if ($missing.Count -gt 0) {
        throw "CLI is missing harness commands: $($missing -join ', ')"
    }
    Write-Host "All harness commands found in CLI help: $($harnessCommands -join ', ')"
}

Write-Host "TIA V18 LAD agent harness offline validation passed."
