param(
    [ValidateSet("Validate", "Probe", "PrepareWorkspace", "ListSessions", "AttachSummary", "ListBlocks", "FindBlock", "ExportBlock", "ParseLad", "ImportXml", "ImportCompile", "CompilePlc", "SaveProject", "RoundTrip", "CleanXml", "ValidateXml")]
    [string]$Task = "Validate",

    [Alias("Pid")]
    [int]$TiaPid = 0,
    [string]$BlockPath = "",
    [string]$Query = "",
    [string]$XmlPath = "",
    [string]$OutDir = "",
    [ValidateSet("block", "type", "tag-table")]
    [string]$Kind = "block",
    [string]$Workspace = "",
    [switch]$NoBuild,
    [switch]$CleanXml,
    [switch]$AllowWrite,
    [string]$OutputPath = "",
    [string]$CompileEvidencePath = "",
    [string]$ExpectedProjectPath = "",
    [string]$ExpectedProjectName = ""
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $HarnessRoot)
$PortableExe = Join-Path $HarnessRoot "tools\bin\AiPlcTiaV18.exe"
$ProjectExe = Join-Path $ProjectRoot "artifacts\bin\AiPlcTiaV18.exe"
$Exe = $PortableExe

function Ensure-Tool {
    if (Test-Path -LiteralPath $PortableExe) {
        $script:Exe = $PortableExe
        return
    }

    if (Test-Path -LiteralPath $ProjectExe) {
        $script:Exe = $ProjectExe
        return
    }

    $buildScript = Join-Path $ProjectRoot "build.ps1"
    if ((Test-Path -LiteralPath $buildScript) -and (-not $NoBuild)) {
        & powershell -ExecutionPolicy Bypass -File $buildScript -Task Build
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if (Test-Path -LiteralPath $ProjectExe) {
            $script:Exe = $ProjectExe
            return
        }
    }

    throw @"
AiPlcTiaV18.exe not found.
Expected either:
  1) portable harness tool: $PortableExe
  2) source-tree build artifact: $ProjectExe

For migration, copy artifacts/bin/AiPlcTiaV18.exe and AiPlcTiaV18.Core.dll into:
  $HarnessRoot\tools\bin\
"@
}

function Invoke-Tool {
    param([string[]]$ToolArgs)
    Ensure-Tool
    Write-Host ("CMD: " + $Exe + " " + ($ToolArgs -join " "))
    & $Exe @ToolArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-ToolCapture {
    param([string[]]$ToolArgs)
    Ensure-Tool
    Write-Host ("CMD: " + $Exe + " " + ($ToolArgs -join " "))
    $output = & $Exe @ToolArgs 2>&1
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line
    }
    return @{
        ExitCode = $exitCode
        Text = (($output | Out-String).Trim())
    }
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

function Require-Pid {
    if ($TiaPid -le 0) { throw "-Pid is required. Run -Task ListSessions first." }
}

function Require-Xml {
    if ([string]::IsNullOrWhiteSpace($XmlPath)) { throw "-XmlPath is required." }
    if (-not (Test-Path -LiteralPath $XmlPath)) { throw "XML path not found: $XmlPath" }
}

function Require-BlockPath {
    if ([string]::IsNullOrWhiteSpace($BlockPath)) { throw "-BlockPath is required. Use a resolved path from AttachSummary, ListBlocks, or FindBlock." }
}

function Resolve-Workspace {
    if ([string]::IsNullOrWhiteSpace($Workspace)) {
        return (Join-Path $HarnessRoot "workspace")
    }
    return $Workspace
}

function Resolve-CompileEvidenceRoot {
    $root = Resolve-Workspace
    $evidenceRoot = Join-Path $root "evidence"
    New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
    return $evidenceRoot
}

function Resolve-DefaultCompileEvidencePath {
    $evidenceRoot = Resolve-CompileEvidenceRoot
    return (Join-Path $evidenceRoot "last-compile.json")
}

function Resolve-CompileEvidencePath {
    $evidenceRoot = Resolve-CompileEvidenceRoot

    if ([string]::IsNullOrWhiteSpace($CompileEvidencePath)) {
        return (Join-Path $evidenceRoot "last-compile.json")
    }

    $candidate = $CompileEvidencePath
    if ([System.IO.Path]::IsPathRooted($CompileEvidencePath)) {
        $candidate = $CompileEvidencePath
    } else {
        $candidate = Join-Path $evidenceRoot $CompileEvidencePath
    }

    $evidenceRootFull = [System.IO.Path]::GetFullPath($evidenceRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $candidateFull = [System.IO.Path]::GetFullPath($candidate)
    if (-not $candidateFull.StartsWith($evidenceRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "-CompileEvidencePath must stay under the current workspace evidence directory: $evidenceRoot"
    }
    return $candidateFull
}

function Remove-CompileEvidence {
    param([switch]$IncludeCustom)

    $paths = @()
    $paths += Resolve-DefaultCompileEvidencePath

    if ($IncludeCustom -and -not [string]::IsNullOrWhiteSpace($CompileEvidencePath)) {
        $customPath = Resolve-CompileEvidencePath
        if ($paths -notcontains $customPath) {
            $paths += $customPath
        }
    }

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "Stale compile evidence removed: $path"
        }
    }
}

function Require-AllowWrite {
    param([string]$Operation)

    if (-not $AllowWrite) {
        throw "$Operation is a write operation. Rerun with -AllowWrite only after explicit approval for the target PID/project/block. Existing-project writes must include -ExpectedProjectPath or -ExpectedProjectName."
    }
}

function Require-ExpectedProjectIdentity {
    param([string]$Operation)

    if ([string]::IsNullOrWhiteSpace($ExpectedProjectPath) -and [string]::IsNullOrWhiteSpace($ExpectedProjectName)) {
        throw "$Operation requires -ExpectedProjectPath or -ExpectedProjectName so the wrapper can verify the intended project before writing."
    }
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-ExpectedProjectMatch {
    if ([string]::IsNullOrWhiteSpace($ExpectedProjectPath) -and [string]::IsNullOrWhiteSpace($ExpectedProjectName)) {
        return
    }

    Require-Pid
    $result = Invoke-ToolCapture @("attach-summary", "--pid", [string]$TiaPid)
    $attach = Assert-ToolResult -Result $result -Step "Expected project check"
    if ($null -eq $attach) {
        throw "Expected project check did not return attach-summary JSON."
    }

    $actualProjectName = [string](Get-JsonProperty -Object $attach -Name "projectName")
    $actualProjectPath = [string](Get-JsonProperty -Object $attach -Name "projectPath")

    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectName)) {
        if ($actualProjectName -ine $ExpectedProjectName) {
            throw "Expected project check failed. Expected projectName '$ExpectedProjectName' but PID $TiaPid is '$actualProjectName'."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectPath)) {
        $expectedFull = Get-NormalizedFullPath -Path $ExpectedProjectPath
        $actualFull = Get-NormalizedFullPath -Path $actualProjectPath
        if ($actualFull -ine $expectedFull) {
            throw "Expected project check failed. Expected projectPath '$expectedFull' but PID $TiaPid is '$actualFull'."
        }
    }

    Write-Host "Expected project check passed: name='$actualProjectName' path='$actualProjectPath'"
}

function Get-JsonProperty {
    param(
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}

function Assert-ToolResult {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,
        [Parameter(Mandatory = $true)]
        [string]$Step
    )

    if ([int]$Result.ExitCode -ne 0) {
        throw "$Step failed with exit code $($Result.ExitCode)."
    }

    $json = ConvertFrom-LastJson -Text ([string]$Result.Text)
    $success = Get-JsonProperty -Object $json -Name "success"
    if (($null -ne $success) -and ($success -ne $true)) {
        $message = [string](Get-JsonProperty -Object $json -Name "message")
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "$Step returned success=false."
        }
        throw "$Step returned success=false. $message"
    }

    return $json
}

function Assert-CompileResultClean {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,
        [Parameter(Mandatory = $true)]
        [string]$Step
    )

    $json = Assert-ToolResult -Result $Result -Step $Step
    if ($null -eq $json) {
        throw "$Step did not return JSON compile evidence."
    }

    $compile = $json
    $nestedCompile = Get-JsonProperty -Object $json -Name "compile"
    if ($nestedCompile) {
        $compile = $nestedCompile
    }

    $success = Get-JsonProperty -Object $compile -Name "success"
    $errorCount = Get-JsonProperty -Object $compile -Name "errorCount"
    if (($success -ne $true) -or ($null -eq $errorCount) -or ([int]$errorCount -ne 0)) {
        throw "$Step compile result is not clean: success=$success errorCount=$errorCount."
    }
}

function Write-CompileEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTask,
        [Parameter(Mandatory = $true)]
        [string[]]$ToolArgs,
        [Parameter(Mandatory = $true)]
        [string]$RawOutput,
        [Parameter(Mandatory = $true)]
        [int]$ExitCode,
        [string]$EvidenceXmlPath = "",
        [string]$EvidenceKind = ""
    )

    $parsed = ConvertFrom-LastJson -Text $RawOutput
    if ($null -eq $parsed) {
        Write-Host "WARNING: compile output was not JSON; guarded save will not be enabled from this run."
    }

    $compile = $parsed
    $nestedCompile = Get-JsonProperty -Object $parsed -Name "compile"
    if ($nestedCompile) {
        $compile = $nestedCompile
    }

    $compileSuccess = Get-JsonProperty -Object $compile -Name "success"
    $errorCount = Get-JsonProperty -Object $compile -Name "errorCount"
    $warningCount = Get-JsonProperty -Object $compile -Name "warningCount"
    $processId = Get-JsonProperty -Object $compile -Name "processId"
    if ($null -eq $processId) {
        $processId = Get-JsonProperty -Object $parsed -Name "processId"
    }

    $evidence = [ordered]@{
        schemaVersion = 1
        sourceTask = $SourceTask
        createdAt = (Get-Date).ToString("o")
        tiaPid = $TiaPid
        processId = $processId
        xmlPath = $EvidenceXmlPath
        kind = $EvidenceKind
        command = ($Exe + " " + ($ToolArgs -join " "))
        exitCode = $ExitCode
        compile = [ordered]@{
            success = $compileSuccess
            errorCount = $errorCount
            warningCount = $warningCount
        }
        rawOutput = $RawOutput
    }

    $path = Resolve-CompileEvidencePath
    $parent = Split-Path -Parent $path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Host "Compile evidence written: $path"
}

function Assert-CompileEvidenceAllowsSave {
    if (-not [string]::IsNullOrWhiteSpace($CompileEvidencePath)) {
        throw "SaveProject is guarded. -CompileEvidencePath is not accepted for save; use the current workspace evidence produced by ImportCompile or live RoundTrip."
    }

    $path = Resolve-CompileEvidencePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "SaveProject is guarded. Compile evidence not found: $path. Run -Task ImportCompile -AllowWrite or live RoundTrip write validation first."
    }

    $evidence = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $createdAtValue = Get-JsonProperty -Object $evidence -Name "createdAt"
    if ($null -eq $createdAtValue) {
        throw "SaveProject is guarded. Last compile evidence is missing createdAt."
    }
    try {
        $createdAt = [DateTimeOffset]::Parse([string]$createdAtValue, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "SaveProject is guarded. Last compile evidence has invalid createdAt: $createdAtValue."
    }
    $maxAge = [TimeSpan]::FromMinutes(30)
    $now = [DateTimeOffset]::Now
    $age = $now - $createdAt
    if ($createdAt -gt $now.AddMinutes(5)) {
        throw "SaveProject is guarded. Last compile evidence is from the future: createdAt=$createdAtValue."
    }
    if ($age -gt $maxAge) {
        throw "SaveProject is guarded. Last compile evidence is stale: age=$([int]$age.TotalMinutes) minutes, max=$([int]$maxAge.TotalMinutes) minutes. Re-run ImportCompile or live RoundTrip write validation."
    }

    $evidencePid = [int](Get-JsonProperty -Object $evidence -Name "tiaPid")
    if ($evidencePid -ne $TiaPid) {
        throw "SaveProject is guarded. Compile evidence PID $evidencePid does not match requested PID $TiaPid."
    }
    $evidenceProcessId = Get-JsonProperty -Object $evidence -Name "processId"
    if ($null -eq $evidenceProcessId) {
        throw "SaveProject is guarded. Last compile evidence is missing processId."
    }
    if ([int]$evidenceProcessId -ne $TiaPid) {
        throw "SaveProject is guarded. Compile evidence processId $evidenceProcessId does not match requested PID $TiaPid."
    }

    $compile = Get-JsonProperty -Object $evidence -Name "compile"
    $sourceTask = [string](Get-JsonProperty -Object $evidence -Name "sourceTask")
    $success = Get-JsonProperty -Object $compile -Name "success"
    $errorCount = Get-JsonProperty -Object $compile -Name "errorCount"
    $exitCode = Get-JsonProperty -Object $evidence -Name "exitCode"
    if ($sourceTask -notin @("ImportCompile", "RoundTripCompile")) {
        throw "SaveProject is guarded. Last compile evidence came from '$sourceTask', not an import/compile write task."
    }
    if ($null -eq $errorCount) {
        throw "SaveProject is guarded. Last compile evidence is missing errorCount."
    }
    if (($exitCode -ne 0) -or ($success -ne $true) -or ([int]$errorCount -ne 0)) {
        throw "SaveProject is guarded. Last compile evidence is not clean: exitCode=$exitCode success=$success errorCount=$errorCount."
    }

    Write-Host "Guarded save allowed by compile evidence: $path"
}

switch ($Task) {
    "Validate" {
        & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot "Test-HarnessOffline.ps1")
        exit $LASTEXITCODE
    }
    "PrepareWorkspace" {
        $root = Resolve-Workspace
        foreach ($name in @("exports", "patched", "reports", "evidence")) {
            New-Item -ItemType Directory -Force -Path (Join-Path $root $name) | Out-Null
        }
        Copy-Item -LiteralPath (Join-Path $HarnessRoot "templates\empty-action-plan.json") -Destination (Join-Path $root "action-plan.json") -Force
        Write-Host "Workspace prepared: $root"
    }
    "Probe" {
        Invoke-Tool @("probe-env")
    }
    "ListSessions" {
        Invoke-Tool @("list-sessions")
    }
    "AttachSummary" {
        Require-Pid
        Invoke-Tool @("attach-summary", "--pid", [string]$TiaPid)
    }
    "ListBlocks" {
        Require-Pid
        if ([string]::IsNullOrWhiteSpace($Query)) {
            Invoke-Tool @("list-blocks", "--pid", [string]$TiaPid)
        } else {
            Invoke-Tool @("list-blocks", "--pid", [string]$TiaPid, "--query", $Query)
        }
    }
    "FindBlock" {
        Require-Pid
        if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($BlockPath)) { throw "-Query or -BlockPath is required." }
        if ([string]::IsNullOrWhiteSpace($Query)) { $Query = $BlockPath }
        $result = Invoke-ToolCapture @("find-block", "--pid", [string]$TiaPid, "--query", $Query)
        [void](Assert-ToolResult -Result $result -Step "FindBlock")
    }
    "ExportBlock" {
        Require-Pid
        if ([string]::IsNullOrWhiteSpace($BlockPath) -and [string]::IsNullOrWhiteSpace($Query)) { throw "-BlockPath or -Query is required." }
        if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path (Resolve-Workspace) "exports" }
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
        if ([string]::IsNullOrWhiteSpace($BlockPath)) {
            $result = Invoke-ToolCapture @("export-block", "--pid", [string]$TiaPid, "--query", $Query, "--out", $OutDir)
        } else {
            $result = Invoke-ToolCapture @("export-block", "--pid", [string]$TiaPid, "--block-path", $BlockPath, "--out", $OutDir)
        }
        [void](Assert-ToolResult -Result $result -Step "ExportBlock")
    }
    "ParseLad" {
        Require-Xml
        $result = Invoke-ToolCapture @("parse-lad", "--xml", $XmlPath, "--block-path", $BlockPath)
        [void](Assert-ToolResult -Result $result -Step "ParseLad")
    }
    "ImportXml" {
        Require-Pid
        Require-AllowWrite -Operation "ImportXml"
        Require-Xml
        Remove-CompileEvidence -IncludeCustom
        Require-ExpectedProjectIdentity -Operation "ImportXml"
        Assert-ExpectedProjectMatch
        $result = Invoke-ToolCapture @("import-xml", "--pid", [string]$TiaPid, "--xml", $XmlPath, "--kind", $Kind)
        [void](Assert-ToolResult -Result $result -Step "ImportXml")
    }
    "ImportCompile" {
        Require-Pid
        Require-AllowWrite -Operation "ImportCompile"
        Require-Xml
        Remove-CompileEvidence -IncludeCustom
        Require-ExpectedProjectIdentity -Operation "ImportCompile"
        Assert-ExpectedProjectMatch
        if ($CleanXml) {
            Write-Host "Cleaning XML namespaces before import..."
            $cleanOut = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
                [System.IO.Path]::ChangeExtension($XmlPath, '.cleaned.xml')
            } else {
                $OutputPath
            }
            & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot "Clean-LadXmlNamespace.ps1") -XmlPath $XmlPath -OutputPath $cleanOut
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $XmlPath = $cleanOut
            Write-Host "Using cleaned XML: $XmlPath"
        }
        $toolArgs = @("import-compile", "--pid", [string]$TiaPid, "--xml", $XmlPath, "--kind", $Kind)
        $result = Invoke-ToolCapture $toolArgs
        Write-CompileEvidence -SourceTask "ImportCompile" -ToolArgs $toolArgs -RawOutput $result.Text -ExitCode $result.ExitCode -EvidenceXmlPath $XmlPath -EvidenceKind $Kind
        Assert-CompileResultClean -Result $result -Step "ImportCompile"
    }
    "CleanXml" {
        Require-Xml
        $cleanArgs = @(
            "-ExecutionPolicy", "Bypass",
            "-File", (Join-Path $ScriptRoot "Clean-LadXmlNamespace.ps1"),
            "-XmlPath", $XmlPath
        )
        if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
            $cleanArgs += @("-OutputPath", $OutputPath)
        }
        & powershell @cleanArgs
        exit $LASTEXITCODE
    }
    "ValidateXml" {
        Require-Xml
        Write-Host "=== Step 1/2: Clean namespace prefixes ==="
        $tempClean = [System.IO.Path]::GetTempFileName() + ".cleaned.xml"
        & powershell -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot "Clean-LadXmlNamespace.ps1") -XmlPath $XmlPath -OutputPath $tempClean
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host "=== Step 2/2: Validate XML well-formed ==="
        try {
            [xml](Get-Content -LiteralPath $tempClean -Raw -Encoding UTF8) | Out-Null
            Write-Host "XML is well-formed after cleaning."
            Remove-Item -LiteralPath $tempClean -Force
        } catch {
            Write-Host "XML is NOT well-formed: $($_.Exception.Message)"
            Write-Host "Cleaned output preserved at: $tempClean"
            exit 1
        }
    }
    "CompilePlc" {
        Require-Pid
        Require-AllowWrite -Operation "CompilePlc"
        Remove-CompileEvidence -IncludeCustom
        Require-ExpectedProjectIdentity -Operation "CompilePlc"
        Assert-ExpectedProjectMatch
        $toolArgs = @("compile-plc", "--pid", [string]$TiaPid)
        $result = Invoke-ToolCapture $toolArgs
        Write-CompileEvidence -SourceTask "CompilePlc" -ToolArgs $toolArgs -RawOutput $result.Text -ExitCode $result.ExitCode
        Assert-CompileResultClean -Result $result -Step "CompilePlc"
    }
    "SaveProject" {
        Require-Pid
        Require-AllowWrite -Operation "SaveProject"
        Assert-CompileEvidenceAllowsSave
        Require-ExpectedProjectIdentity -Operation "SaveProject"
        Assert-ExpectedProjectMatch
        Invoke-Tool @("save-project", "--pid", [string]$TiaPid)
    }
    "RoundTrip" {
        Require-Pid
        Require-BlockPath
        if (-not [string]::IsNullOrWhiteSpace($XmlPath)) {
            Require-AllowWrite -Operation "RoundTrip import"
            Require-Xml
            Remove-CompileEvidence -IncludeCustom
            Require-ExpectedProjectIdentity -Operation "RoundTrip import"
            Assert-ExpectedProjectMatch
        }
        Ensure-Tool
        $root = Resolve-Workspace
        foreach ($name in @("exports", "patched", "reports", "evidence")) {
            New-Item -ItemType Directory -Force -Path (Join-Path $root $name) | Out-Null
        }
        # Step 0: discover actual block path before exporting (block may be under
        # a non-default group like "程序块" or "PLC_1/Program blocks")
        Write-Host "Discovering block path for '$BlockPath'..."
        $discovered = & $Exe list-blocks --pid ([string]$TiaPid) --query $BlockPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $discovered) {
            $resolved = ($discovered | ForEach-Object { $_ } | Select-String -Pattern '"resolvedBlockPath"\s*:\s*"([^"]+)"').Matches
            if ($resolved -and $resolved.Count -gt 0) {
                $BlockPath = $resolved[0].Groups[1].Value
                Write-Host "Resolved block path: $BlockPath"
            }
        } else {
            Write-Host "list-blocks failed or returned empty; proceeding with provided -BlockPath: $BlockPath"
        }
        $exportResult = Invoke-ToolCapture @("export-block", "--pid", [string]$TiaPid, "--block-path", $BlockPath, "--out", (Join-Path $root "exports"))
        [void](Assert-ToolResult -Result $exportResult -Step "RoundTrip export")
        if (-not [string]::IsNullOrWhiteSpace($XmlPath)) {
            $parseResult = Invoke-ToolCapture @("parse-lad", "--xml", $XmlPath, "--block-path", $BlockPath)
            [void](Assert-ToolResult -Result $parseResult -Step "RoundTrip parse")
            $importResult = Invoke-ToolCapture @("import-xml", "--pid", [string]$TiaPid, "--xml", $XmlPath, "--kind", $Kind)
            [void](Assert-ToolResult -Result $importResult -Step "RoundTrip import")
            $toolArgs = @("compile-plc", "--pid", [string]$TiaPid)
            $result = Invoke-ToolCapture $toolArgs
            Write-CompileEvidence -SourceTask "RoundTripCompile" -ToolArgs $toolArgs -RawOutput $result.Text -ExitCode $result.ExitCode -EvidenceXmlPath $XmlPath -EvidenceKind $Kind
            Assert-CompileResultClean -Result $result -Step "RoundTrip compile"
            Write-Host "RoundTrip imported and compiled. -Task SaveProject is now guarded by workspace\evidence\last-compile.json."
        } else {
            Write-Host "Export completed. Copy/edit XML into workspace\patched, then rerun RoundTrip with -XmlPath <patched xml>."
        }
    }
}
