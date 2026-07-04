param(
    [string]$TargetRoot = "",
    [string]$ProjectName = "",
    [string]$DeviceName = "PLC_1",
    [string]$BlockName = "FB_HarnessGate3",
    [string[]]$DeviceTypeIdentifier = @(),
    [ValidateSet("WithUserInterface", "WithoutUserInterface")]
    [string]$PortalMode = "WithUserInterface",
    [switch]$AllowCreate,
    [switch]$Force,
    [switch]$CloseAfterCreate,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $HarnessRoot)
$PortableExe = Join-Path $HarnessRoot "tools\bin\AiPlcTiaV18.exe"
$ProjectExe = Join-Path $ProjectRoot "artifacts\bin\AiPlcTiaV18.exe"
$Exe = $PortableExe

if (-not $AllowCreate) {
    throw "Creating a TIA project is a state-changing operation. Rerun with -AllowCreate only for a disposable test project."
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
}

function Assert-TargetRootUnderTemp {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $tempRoot = Get-NormalizedFullPath -Path $env:TEMP
    $targetFull = Get-NormalizedFullPath -Path $Path
    $tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (($targetFull -ieq $tempRoot) -or $targetFull.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }
    throw "-TargetRoot must stay under the current TEMP directory for disposable project creation. TEMP=$tempRoot TargetRoot=$targetFull"
}

function Assert-SafeName {
    param([string]$Name, [string]$ParamName)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "$ParamName must be a non-empty single name."
    }
    if ([System.IO.Path]::IsPathRooted($Name)) {
        throw "$ParamName must not be an absolute path: $Name"
    }
    if ($Name -in @(".", "..")) {
        throw "$ParamName must not be '.' or '..'."
    }
    if ($Name.EndsWith(".") -or $Name.EndsWith(" ")) {
        throw "$ParamName must not end with a dot or space: $Name"
    }
    if (($Name.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0) -or
        ($Name.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0)) {
        throw "$ParamName must not contain path separators: $Name"
    }
    foreach ($invalid in [System.IO.Path]::GetInvalidFileNameChars()) {
        if ($Name.IndexOf($invalid) -ge 0) {
            throw "$ParamName contains an invalid filename character: $Name"
        }
    }
    $baseName = ($Name -split '\.')[0].ToUpperInvariant()
    if ($baseName -in @("CON", "PRN", "AUX", "NUL") -or $baseName -match '^(COM|LPT)[1-9]$') {
        throw "$ParamName must not be a Windows reserved device name: $Name"
    }
}

Assert-TargetRootUnderTemp -Path $TargetRoot
if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
    Assert-SafeName -Name $ProjectName -ParamName "-ProjectName"
}
Assert-SafeName -Name $DeviceName -ParamName "-DeviceName"
Assert-SafeName -Name $BlockName -ParamName "-BlockName"

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

Ensure-Tool

$toolArgs = @(
    "create-disposable-lad-project",
    "--allow-create",
    "--device-name", $DeviceName,
    "--seed-block-name", $BlockName,
    "--portal-mode", $PortalMode
)

if (-not [string]::IsNullOrWhiteSpace($TargetRoot)) {
    $toolArgs += @("--target-root", $TargetRoot)
}
if (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
    $toolArgs += @("--project-name", $ProjectName)
}
foreach ($identifier in @($DeviceTypeIdentifier)) {
    if (-not [string]::IsNullOrWhiteSpace($identifier)) {
        $toolArgs += @("--device-type-identifier", $identifier)
    }
}
if ($Force) {
    $toolArgs += "--force"
}
if ($CloseAfterCreate) {
    $toolArgs += "--close-after-create"
}

Write-Host ("CMD: " + $Exe + " " + ($toolArgs -join " "))
& $Exe @toolArgs
exit $LASTEXITCODE
