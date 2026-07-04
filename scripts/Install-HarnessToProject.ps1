param(
    [Parameter(Mandatory = $true)]
    [string]$TargetRoot,

    [string]$HarnessName = "tia-v18-lad-agent",

    [switch]$Force,

    [switch]$IncludeWorkspaceArtifacts,

    [switch]$SkipAgentPointers,

    [switch]$ForceAgentPointers
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot

function Assert-SafeHarnessName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "-HarnessName must be a single directory name."
    }
    if ([System.IO.Path]::IsPathRooted($Name)) {
        throw "-HarnessName must not be an absolute path: $Name"
    }
    if ($Name -in @(".", "..")) {
        throw "-HarnessName must not be '.' or '..'."
    }
    if ($Name.EndsWith(".") -or $Name.EndsWith(" ")) {
        throw "-HarnessName must not end with a dot or space: $Name"
    }
    if (($Name.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0) -or
        ($Name.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0)) {
        throw "-HarnessName must not contain path separators: $Name"
    }
    foreach ($invalid in [System.IO.Path]::GetInvalidFileNameChars()) {
        if ($Name.IndexOf($invalid) -ge 0) {
            throw "-HarnessName contains an invalid filename character: $Name"
        }
    }

    $baseName = ($Name -split '\.')[0].ToUpperInvariant()
    if ($baseName -in @("CON", "PRN", "AUX", "NUL") -or $baseName -match '^(COM|LPT)[1-9]$') {
        throw "-HarnessName must not be a Windows reserved device name: $Name"
    }
}

function Ensure-ChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Parent,
        [Parameter(Mandatory = $true)]
        [string]$Child
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $childFull = [System.IO.Path]::GetFullPath($Child)
    if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside target root. TargetRoot=$parentFull Destination=$childFull"
    }
    if ($childFull.TrimEnd('\', '/') -ieq $parentFull.TrimEnd('\', '/')) {
        throw "Refusing to operate on the target root itself: $childFull"
    }
    return $childFull
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-ExistingDestinationIsReplaceableHarness {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$SourceHarnessRoot
    )

    $item = Get-Item -LiteralPath $Destination -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to replace reparse point destination: $Destination"
    }

    $destinationFull = Get-NormalizedFullPath -Path $item.FullName
    $sourceFull = Get-NormalizedFullPath -Path $SourceHarnessRoot
    if ($destinationFull -ieq $sourceFull) {
        throw "Refusing to replace the source harness directory: $destinationFull"
    }

    $requiredMarkers = @(
        "harness.json",
        "AGENTS.md",
        "scripts\Invoke-TiaV18LadHarness.ps1",
        "tools\bin\AiPlcTiaV18.exe"
    )
    $missing = @($requiredMarkers | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $Destination $_) -PathType Leaf)
    })
    if ($missing.Count -gt 0) {
        throw "Destination exists but does not look like a harness; missing marker(s): $($missing -join ', '). Refusing to remove: $Destination"
    }
}

Assert-SafeHarnessName -Name $HarnessName

if (-not (Test-Path -LiteralPath $TargetRoot)) {
    New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
}

$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path
$Destination = Join-Path $TargetRoot $HarnessName
$Destination = Ensure-ChildPath -Parent $TargetRoot -Child $Destination

if (Test-Path -LiteralPath $Destination) {
    if (-not $Force) {
        throw "Destination already exists: $Destination. Re-run with -Force to replace it."
    }
    Assert-ExistingDestinationIsReplaceableHarness -Destination $Destination -SourceHarnessRoot $HarnessRoot
    Remove-Item -LiteralPath $Destination -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$skipDirs = @("__pycache__")
$skipExtensions = @(".pyc")
$workspaceRootPrefix = "workspace\"

function Should-SkipFile {
    param([string]$RelativePath)

    foreach ($dir in $skipDirs) {
        if ($RelativePath -match "(^|\\)$([regex]::Escape($dir))(\\|$)") {
            return $true
        }
    }

    $extension = [System.IO.Path]::GetExtension($RelativePath)
    if ($skipExtensions -contains $extension) {
        return $true
    }

    if (-not $IncludeWorkspaceArtifacts -and $RelativePath.StartsWith($workspaceRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($RelativePath -ine "workspace\README.md") {
            return $true
        }
    }

    return $false
}

function Write-AgentPointer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$HarnessName
    )

    $target = Join-Path $TargetRoot $RelativePath
    $target = Ensure-ChildPath -Parent $TargetRoot -Child $target
    if ((Test-Path -LiteralPath $target) -and (-not $ForceAgentPointers)) {
        Write-Host "Agent pointer exists, leaving unchanged: $target"
        return
    }

    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    if ($RelativePath -ieq ".aider.conf.yml") {
        $aiderContent = @"
read:
  - ${HarnessName}/AGENTS.md
  - ${HarnessName}/harness.json
  - ${HarnessName}/docs/editing-contract.md
  - ${HarnessName}/docs/validation-gates.md
  - ${HarnessName}/docs/wiki/architecture.md
  - ${HarnessName}/docs/wiki/safety-gates.md
  - ${HarnessName}/docs/wiki/existing-project-readwrite.md
  - ${HarnessName}/docs/development-todo.md
"@
        Set-Content -LiteralPath $target -Value $aiderContent -Encoding UTF8
        Write-Host "Agent pointer written: $target"
        return
    }

    $content = @"
# TIA V18 LAD Harness Pointer

Before editing any Siemens TIA Portal PLC logic in this workspace, read and
follow:

1. ${HarnessName}/AGENTS.md
2. ${HarnessName}/harness.json
3. ${HarnessName}/docs/editing-contract.md
4. ${HarnessName}/docs/validation-gates.md
5. ${HarnessName}/docs/wiki/safety-gates.md
6. ${HarnessName}/docs/wiki/existing-project-readwrite.md
7. ${HarnessName}/docs/development-todo.md

Use only wrapper commands under ${HarnessName}/scripts/. Import, standalone
compile, and save operations require explicit approval and -AllowWrite.
Existing-project writes must include -ExpectedProjectPath. If validating an
already-open real project, do not create a new TIA project; first use unchanged
self-import, clean compile evidence, and no save until the save gate is
explicitly approved. Disposable creation is deferred/fallback support and
requires separate -AllowCreate. Never call the raw CLI for write/save
operations.
"@
    Set-Content -LiteralPath $target -Value $content -Encoding UTF8
    Write-Host "Agent pointer written: $target"
}

$files = Get-ChildItem -LiteralPath $HarnessRoot -File -Recurse
foreach ($file in $files) {
    $relative = $file.FullName.Substring($HarnessRoot.Length).TrimStart("\", "/")
    if (Should-SkipFile -RelativePath $relative) {
        continue
    }

    $target = Join-Path $Destination $relative
    $targetDir = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}

foreach ($dir in @("workspace", "workspace\exports", "workspace\patched", "workspace\reports", "workspace\evidence")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Destination $dir) | Out-Null
}

if (-not $SkipAgentPointers) {
    Write-AgentPointer -RelativePath "AGENTS.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "CLAUDE.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "GEMINI.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "COPILOT.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "KILO.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "ROO.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "CONTINUE.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "AIDER.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath "CONVENTIONS.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".aider.conf.yml" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".cursorrules" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".cursor\rules\tia-v18-lad-agent.mdc" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".github\copilot-instructions.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".github\instructions\tia-v18-lad.instructions.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".kilo\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".kilocode\rules.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".kilocode\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".roo\rules.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".roo\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".roorules" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".windsurfrules" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".windsurf\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".continue\rules.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".continue\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".devin\rules\tia-v18-lad-harness.md" -HarnessName $HarnessName
    Write-AgentPointer -RelativePath ".clinerules\tia-v18-lad-harness.md" -HarnessName $HarnessName
}

$toolExe = Join-Path $Destination "tools\bin\AiPlcTiaV18.exe"
$toolDll = Join-Path $Destination "tools\bin\AiPlcTiaV18.Core.dll"
if (-not (Test-Path -LiteralPath $toolExe)) { throw "Portable CLI missing after copy: $toolExe" }
if (-not (Test-Path -LiteralPath $toolDll)) { throw "Portable CLI dependency missing after copy: $toolDll" }

Write-Host "Harness installed: $Destination"
if (-not $SkipAgentPointers) {
    Write-Host "Project-root agent pointers installed when absent. Existing files were not overwritten unless -ForceAgentPointers was used."
}
Write-Host "Next:"
Write-Host "  cd `"$Destination`""
Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\Test-HarnessOffline.ps1"
