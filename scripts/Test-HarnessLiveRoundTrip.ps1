param(
    [Alias("Pid")]
    [int]$TiaPid = 0,

    [string]$Query = "",
    [string]$BlockPath = "",
    [string]$PatchedXmlPath = "",

    [ValidateSet("block", "type", "tag-table")]
    [string]$Kind = "block",

    [string]$Workspace = "",
    [string]$ReportPath = "",
    [string]$ExpectedProjectPath = "",
    [string]$ExpectedProjectName = "",

    [switch]$CleanXml,
    [switch]$AllowWrite,
    [switch]$SelfImportExportedXml,
    [switch]$Save,
    [switch]$DiscoveryOnly,
    [switch]$SkipOfflineValidation
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot
$Runner = Join-Path $ScriptRoot "Invoke-TiaV18LadHarness.ps1"
$OfflineValidator = Join-Path $ScriptRoot "Test-HarnessOffline.ps1"

function Resolve-Workspace {
    if ([string]::IsNullOrWhiteSpace($Workspace)) {
        return (Join-Path $HarnessRoot "workspace")
    }
    if ([System.IO.Path]::IsPathRooted($Workspace)) {
        return $Workspace
    }
    return (Join-Path $HarnessRoot $Workspace)
}

function ConvertFrom-LastJson {
    param([string]$Text)

    $lines = @($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i].Trim()
        if ($line.StartsWith("{") -or $line.StartsWith("[")) {
            try {
                return ($line | ConvertFrom-Json)
            } catch {
                return $null
            }
        }
    }
    return $null
}

function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}

function Assert-HarnessResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,
        [Parameter(Mandatory = $true)]
        [string]$Step
    )

    if ($Result.ExitCode -ne 0) {
        throw "$Step failed with exit code $($Result.ExitCode)."
    }

    $success = Get-JsonProperty -Object $Result.Json -Name "success"
    if (($null -ne $success) -and ($success -ne $true)) {
        $message = [string](Get-JsonProperty -Object $Result.Json -Name "message")
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "$Step returned success=false."
        }
        throw "$Step returned success=false. $message"
    }
}

function Get-AttachedBlockSummaries {
    param(
        [object]$AttachJson,
        [string]$Language = ""
    )

    $result = @()
    $plcSoftwares = @(Get-JsonProperty -Object $AttachJson -Name "plcSoftwares")
    foreach ($plc in $plcSoftwares) {
        if ($null -eq $plc) { continue }
        $plcName = [string](Get-JsonProperty -Object $plc -Name "name")
        $blocks = @(Get-JsonProperty -Object $plc -Name "blocks")
        foreach ($block in $blocks) {
            if ($null -eq $block) { continue }
            $languageValue = [string](Get-JsonProperty -Object $block -Name "programmingLanguage")
            if ((-not [string]::IsNullOrWhiteSpace($Language)) -and ($languageValue -ine $Language)) {
                continue
            }

            $path = [string](Get-JsonProperty -Object $block -Name "path")
            $typeName = [string](Get-JsonProperty -Object $block -Name "typeName")
            if ([string]::IsNullOrWhiteSpace($path)) { continue }
            if ([string]::IsNullOrWhiteSpace($plcName)) {
                $result += "$path [$typeName/$languageValue]"
            } else {
                $result += "$plcName :: $path [$typeName/$languageValue]"
            }
        }
    }

    return $result
}

function Add-BlockQueryHint {
    param([object]$AttachJson)

    $ladBlocks = @(Get-AttachedBlockSummaries -AttachJson $AttachJson -Language "LAD")
    if ($ladBlocks.Count -eq 0) {
        Add-ReportLine "- AvailableLadBlocks: none found in attach summary"
        Write-Host "No LAD blocks were found in attach summary."
        return
    }

    Add-ReportLine "### Available LAD blocks"
    Write-Host "Available LAD blocks for -Query or -BlockPath:"
    foreach ($block in $ladBlocks) {
        Add-ReportLine ('- `' + $block + '`')
        Write-Host "  - $block"
    }
}

function Invoke-HarnessTask {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $display = "powershell -ExecutionPolicy Bypass -File `"$Runner`" " + ($Arguments -join " ")
    Write-Host "=== $display ==="
    $output = & powershell -ExecutionPolicy Bypass -File $Runner @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line
    }
    $text = ($output | Out-String).Trim()
    return [pscustomobject]@{
        Command = $display
        ExitCode = $exitCode
        Text = $text
        Json = ConvertFrom-LastJson -Text $text
    }
}

function Add-ReportLine {
    param([string]$Line)
    $script:ReportLines += $Line
}

$workspaceRoot = Resolve-Workspace
foreach ($name in @("exports", "patched", "reports", "evidence")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $workspaceRoot $name) | Out-Null
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $ReportPath = Join-Path (Join-Path $workspaceRoot "reports") "live-roundtrip-$stamp.md"
} elseif (-not [System.IO.Path]::IsPathRooted($ReportPath)) {
    $ReportPath = Join-Path $HarnessRoot $ReportPath
}

$script:ReportLines = @()
Add-ReportLine "# TIA V18 LAD Harness Live Round-Trip Report"
Add-ReportLine ""
Add-ReportLine "- Created: $(Get-Date -Format o)"
Add-ReportLine "- Harness: $HarnessRoot"
Add-ReportLine "- Workspace: $workspaceRoot"
if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectPath)) {
    Add-ReportLine "- ExpectedProjectPath: $ExpectedProjectPath"
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectName)) {
    Add-ReportLine "- ExpectedProjectName: $ExpectedProjectName"
}
Add-ReportLine ""

try {
    if ($SelfImportExportedXml -and (-not [string]::IsNullOrWhiteSpace($PatchedXmlPath))) {
        throw "Use either -SelfImportExportedXml or -PatchedXmlPath, not both."
    }

    if (($SelfImportExportedXml -or (-not [string]::IsNullOrWhiteSpace($PatchedXmlPath))) -and (-not $AllowWrite)) {
        throw "-SelfImportExportedXml and -PatchedXmlPath are write intents. Add -AllowWrite only after explicit approval and preferably against a test project."
    }

    if ($Save -and (-not $AllowWrite)) {
        throw "-Save requires -AllowWrite and clean compile evidence from an import/compile step."
    }

    if ($Save -and (-not $SelfImportExportedXml) -and [string]::IsNullOrWhiteSpace($PatchedXmlPath)) {
        throw "-Save requires -SelfImportExportedXml or -PatchedXmlPath so an import/compile step can produce same-PID evidence."
    }

    if (-not $SkipOfflineValidation) {
        Add-ReportLine "## Offline Validation"
        Write-Host "=== powershell -ExecutionPolicy Bypass -File `"$OfflineValidator`" ==="
        & powershell -ExecutionPolicy Bypass -File $OfflineValidator
        $offlineExit = $LASTEXITCODE
        Add-ReportLine "- ExitCode: $offlineExit"
        if ($offlineExit -ne 0) { exit $offlineExit }
        Add-ReportLine ""
    }

    Add-ReportLine "## Probe"
    $probe = Invoke-HarnessTask @("-Task", "Probe", "-Workspace", $workspaceRoot)
    Add-ReportLine "- ExitCode: $($probe.ExitCode)"
    Assert-HarnessResult -Result $probe -Step "Probe"
    Add-ReportLine ""

    Add-ReportLine "## ListSessions"
    $sessionsResult = Invoke-HarnessTask @("-Task", "ListSessions", "-Workspace", $workspaceRoot)
    Add-ReportLine "- ExitCode: $($sessionsResult.ExitCode)"
    Assert-HarnessResult -Result $sessionsResult -Step "ListSessions"

    $sessions = @()
    if ($null -eq $sessionsResult.Json) {
        $sessions = @()
    } elseif ($sessionsResult.Json -is [array]) {
        $sessions = @($sessionsResult.Json)
    } else {
        $sessions = @($sessionsResult.Json)
    }
    Add-ReportLine "- SessionCount: $($sessions.Count)"
    if ($TiaPid -le 0) {
        if ($sessions.Count -eq 1) {
            $TiaPid = [int](Get-JsonProperty -Object $sessions[0] -Name "processId")
            Add-ReportLine "- SelectedPid: $TiaPid"
            Write-Host "Selected only TIA session PID: $TiaPid"
        } elseif ($sessions.Count -eq 0) {
            throw "No attachable TIA Portal sessions found. Open the target TIA V18 project and rerun."
        } else {
            throw "Multiple TIA Portal sessions found. Rerun with -Pid <processId>."
        }
    } else {
        Add-ReportLine "- RequestedPid: $TiaPid"
    }
    Add-ReportLine ""

    Add-ReportLine "## AttachSummary"
    $attach = Invoke-HarnessTask @("-Task", "AttachSummary", "-Pid", [string]$TiaPid, "-Workspace", $workspaceRoot)
    Add-ReportLine "- ExitCode: $($attach.ExitCode)"
    Assert-HarnessResult -Result $attach -Step "AttachSummary"
    Add-ReportLine ""

    if ($DiscoveryOnly) {
        Add-ReportLine "## Result"
        Add-ReportLine "- DiscoveryOnly: true"
        return
    }

    if ([string]::IsNullOrWhiteSpace($BlockPath) -and [string]::IsNullOrWhiteSpace($Query)) {
        throw "Provide -BlockPath or -Query unless -DiscoveryOnly is used."
    }

    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        Add-ReportLine "## FindBlock"
        $find = Invoke-HarnessTask @("-Task", "FindBlock", "-Pid", [string]$TiaPid, "-Query", $Query, "-Workspace", $workspaceRoot)
        Add-ReportLine "- ExitCode: $($find.ExitCode)"
        try {
            Assert-HarnessResult -Result $find -Step "FindBlock"
        } catch {
            Add-BlockQueryHint -AttachJson $attach.Json
            throw
        }
        $resolved = Get-JsonProperty -Object $find.Json -Name "resolvedBlockPath"
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            $BlockPath = [string]$resolved
            Add-ReportLine ('- ResolvedBlockPath: `' + $BlockPath + '`')
        }
        Add-ReportLine ""
    }

    if ([string]::IsNullOrWhiteSpace($BlockPath)) {
        Add-BlockQueryHint -AttachJson $attach.Json
        throw "Block path could not be resolved."
    }

    Add-ReportLine "## ExportBlock"
    $exportArgs = @("-Task", "ExportBlock", "-Pid", [string]$TiaPid, "-BlockPath", $BlockPath, "-OutDir", (Join-Path $workspaceRoot "exports"), "-Workspace", $workspaceRoot)
    $export = Invoke-HarnessTask $exportArgs
    Add-ReportLine "- ExitCode: $($export.ExitCode)"
    Assert-HarnessResult -Result $export -Step "ExportBlock"
    $exportPath = [string](Get-JsonProperty -Object $export.Json -Name "exportPath")
    $baseHash = [string](Get-JsonProperty -Object $export.Json -Name "baseHash")
    Add-ReportLine ('- ExportPath: `' + $exportPath + '`')
    Add-ReportLine ('- BaseHash: `' + $baseHash + '`')
    Add-ReportLine ""

    if (-not [string]::IsNullOrWhiteSpace($exportPath) -and (Test-Path -LiteralPath $exportPath)) {
        Add-ReportLine "## ParseLad"
        $parse = Invoke-HarnessTask @("-Task", "ParseLad", "-BlockPath", $BlockPath, "-XmlPath", $exportPath, "-Workspace", $workspaceRoot)
        Add-ReportLine "- ExitCode: $($parse.ExitCode)"
        Assert-HarnessResult -Result $parse -Step "ParseLad"
        Add-ReportLine ""
    }

    if ($SelfImportExportedXml) {
        if ([string]::IsNullOrWhiteSpace($exportPath) -or (-not (Test-Path -LiteralPath $exportPath))) {
            throw "Cannot self-import because the exported XML path is missing or does not exist."
        }
        $PatchedXmlPath = $exportPath
        Add-ReportLine "## Write Test Input"
        Add-ReportLine "- SelfImportExportedXml: true"
        Add-ReportLine ('- XmlPath: `' + $PatchedXmlPath + '`')
        Add-ReportLine "- Scope: unchanged exported XML"
        Add-ReportLine ""
    }

    if ([string]::IsNullOrWhiteSpace($PatchedXmlPath)) {
        Add-ReportLine "## Result"
        Add-ReportLine "- ExportAndParseOnly: true"
        Add-ReportLine '- Next: for existing-project proof, rerun with `-ExpectedProjectPath <approved .ap18> -SelfImportExportedXml -AllowWrite`; for a reviewed patch, rerun with `-PatchedXmlPath <file> -ExpectedProjectPath <approved .ap18> -AllowWrite`.'
        return
    }

    if (-not $AllowWrite) {
        Add-ReportLine "## Write Gate"
        Add-ReportLine "- AllowWrite: false"
        Add-ReportLine "- Result: refused before import"
        throw "Patched XML import is a write operation. Rerun with -AllowWrite only after explicit user approval and preferably against a test project."
    }

    if (-not (Test-Path -LiteralPath $PatchedXmlPath)) {
        throw "Patched XML not found: $PatchedXmlPath"
    }

    Add-ReportLine "## ImportCompile"
    $importArgs = @("-Task", "ImportCompile", "-Pid", [string]$TiaPid, "-XmlPath", $PatchedXmlPath, "-Kind", $Kind, "-Workspace", $workspaceRoot, "-AllowWrite")
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectPath)) { $importArgs += @("-ExpectedProjectPath", $ExpectedProjectPath) }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectName)) { $importArgs += @("-ExpectedProjectName", $ExpectedProjectName) }
    if ($CleanXml) { $importArgs += "-CleanXml" }
    $importCompile = Invoke-HarnessTask $importArgs
    Add-ReportLine "- ExitCode: $($importCompile.ExitCode)"
    Assert-HarnessResult -Result $importCompile -Step "ImportCompile"
    $compileEvidence = Join-Path (Join-Path $workspaceRoot "evidence") "last-compile.json"
    Add-ReportLine ('- CompileEvidence: `' + $compileEvidence + '`')
    Add-ReportLine ""

    if ($Save) {
        Add-ReportLine "## SaveProject"
        $saveArgs = @("-Task", "SaveProject", "-Pid", [string]$TiaPid, "-Workspace", $workspaceRoot, "-AllowWrite")
        if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectPath)) { $saveArgs += @("-ExpectedProjectPath", $ExpectedProjectPath) }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectName)) { $saveArgs += @("-ExpectedProjectName", $ExpectedProjectName) }
        $save = Invoke-HarnessTask $saveArgs
        Add-ReportLine "- ExitCode: $($save.ExitCode)"
        Assert-HarnessResult -Result $save -Step "SaveProject"
    } else {
        Add-ReportLine "## SaveProject"
        Add-ReportLine "- Skipped: true"
        Add-ReportLine '- Reason: pass `-Save` to perform guarded save after reviewing compile evidence and explicit save approval.'
    }
} finally {
    $reportParent = Split-Path -Parent $ReportPath
    if ($reportParent -and -not (Test-Path -LiteralPath $reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }
    $script:ReportLines | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "Live round-trip report: $ReportPath"
}
