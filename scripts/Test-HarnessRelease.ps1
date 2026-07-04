param(
    [string]$ZipPath = "",
    [switch]$SkipZip,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessRoot = Split-Path -Parent $ScriptRoot
$HarnessName = Split-Path -Leaf $HarnessRoot
$Runner = Join-Path $ScriptRoot "Invoke-TiaV18LadHarness.ps1"
$OfflineValidator = Join-Path $ScriptRoot "Test-HarnessOffline.ps1"
$Installer = Join-Path $ScriptRoot "Install-HarnessToProject.ps1"
$DisposableProjectPrep = Join-Path $ScriptRoot "New-TiaV18DisposableLadProject.ps1"

function New-TempDir {
    param([string]$Prefix)

    $path = Join-Path $env:TEMP ($Prefix + "-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Remove-TempDir {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $resolved = (Resolve-Path $Path -ErrorAction SilentlyContinue).Path
    if ($resolved -and $resolved.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

function Invoke-ScriptForTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [Parameter(Mandatory = $true)]
        [string]$TempRoot
    )

    $outFile = Join-Path $TempRoot ([guid]::NewGuid().ToString("N") + ".out.txt")
    $errFile = Join-Path $TempRoot ([guid]::NewGuid().ToString("N") + ".err.txt")
    function Quote-ProcessArgument {
        param([string]$Argument)

        if ($null -eq $Argument) { return '""' }
        if ($Argument.Length -eq 0) { return '""' }
        if ($Argument -notmatch '[\s"]') { return $Argument }
        return '"' + ($Argument -replace '(\\*)"', '$1$1\"') + '"'
    }

    $argList = (@("-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $ScriptArgs |
        ForEach-Object { Quote-ProcessArgument -Argument $_ }) -join " "
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden -Wait -PassThru
    $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
    return @{
        ExitCode = $process.ExitCode
        Text = (($stdout + "`n" + $stderr).Trim())
    }
}

function Expect-Failure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$TempRoot,
        [switch]$MayReachCli
    )

    $result = Invoke-ScriptForTest -ScriptPath $ScriptPath -ScriptArgs $ScriptArgs -TempRoot $TempRoot
    if ($result.ExitCode -eq 0) {
        throw "$Name unexpectedly succeeded. Output: $($result.Text)"
    }
    if ($result.Text -notmatch [regex]::Escape($Pattern)) {
        throw "$Name failed with unexpected output: $($result.Text)"
    }
    if ((-not $MayReachCli) -and ($result.Text -match "CMD:")) {
        throw "$Name reached CLI unexpectedly: $($result.Text)"
    }
    Write-Host "Expected failure OK: $Name"
}

function Expect-Success {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [Parameter(Mandatory = $true)]
        [string]$TempRoot
    )

    $result = Invoke-ScriptForTest -ScriptPath $ScriptPath -ScriptArgs $ScriptArgs -TempRoot $TempRoot
    if ($result.ExitCode -ne 0) {
        throw "$Name failed unexpectedly. Output: $($result.Text)"
    }
    Write-Host "Expected success OK: $Name"
    return $result
}

function Assert-FileExists {
    param([string]$Path, [string]$Description)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing ${Description}: $Path"
    }
}

function New-FakeCliExe {
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $source = @'
using System;
using System.Linq;

public static class Program
{
    private static string ValueAfter(string[] args, string name, string fallback)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (String.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }
        return fallback;
    }

    public static int Main(string[] args)
    {
        string command = args.Length > 0 ? args[0] : "";
        string pid = ValueAfter(args, "--pid", "999999");
        bool fail = args.Any(a => a.IndexOf("fail", StringComparison.OrdinalIgnoreCase) >= 0);
        Console.WriteLine("fake-cli " + String.Join(" ", args));

        if (String.Equals(command, "import-compile", StringComparison.OrdinalIgnoreCase) ||
            String.Equals(command, "compile-plc", StringComparison.OrdinalIgnoreCase))
        {
            if (fail)
            {
                Console.WriteLine("{\"success\":false,\"processId\":" + pid + ",\"compile\":{\"success\":false,\"errorCount\":1,\"warningCount\":0}}");
                return 2;
            }
            Console.WriteLine("{\"success\":true,\"processId\":" + pid + ",\"compile\":{\"success\":true,\"errorCount\":0,\"warningCount\":0}}");
            return 0;
        }

        if (String.Equals(command, "attach-summary", StringComparison.OrdinalIgnoreCase))
        {
            Console.WriteLine("{\"processId\":" + pid + ",\"projectName\":\"FakeProject\",\"projectPath\":\"C:\\\\Temp\\\\FakeProject.ap18\",\"plcSoftwares\":[]}");
            return 0;
        }

        Console.WriteLine("{\"success\":true,\"processId\":" + pid + "}");
        return fail ? 2 : 0;
    }
}
'@
    Add-Type -TypeDefinition $source -OutputAssembly $Path -OutputType ConsoleApplication
}

function Test-SafetyGuards {
    Write-Host "Checking offline safety guard regressions..."
    $tempRoot = New-TempDir -Prefix "tia-harness-release-safety"
    try {
        $workspace = Join-Path $tempRoot "workspace"
        New-Item -ItemType Directory -Force -Path $workspace | Out-Null
        $xml = Join-Path $tempRoot "dummy.xml"
        Set-Content -LiteralPath $xml -Encoding UTF8 -Value "<root />"

        Expect-Failure -Name "ImportXml without AllowWrite" -ScriptPath $Runner -ScriptArgs @("-Task", "ImportXml", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $workspace) -Pattern "ImportXml is a write operation" -TempRoot $tempRoot
        Expect-Failure -Name "ImportCompile without AllowWrite" -ScriptPath $Runner -ScriptArgs @("-Task", "ImportCompile", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $workspace) -Pattern "ImportCompile is a write operation" -TempRoot $tempRoot
        Expect-Failure -Name "CompilePlc without AllowWrite" -ScriptPath $Runner -ScriptArgs @("-Task", "CompilePlc", "-Pid", "999999", "-Workspace", $workspace) -Pattern "CompilePlc is a write operation" -TempRoot $tempRoot
        Expect-Failure -Name "RoundTrip import without AllowWrite" -ScriptPath $Runner -ScriptArgs @("-Task", "RoundTrip", "-Pid", "999999", "-BlockPath", "DummyBlock", "-XmlPath", $xml, "-Workspace", $workspace) -Pattern "RoundTrip import is a write operation" -TempRoot $tempRoot
        Expect-Failure -Name "ImportXml with AllowWrite requires project identity" -ScriptPath $Runner -ScriptArgs @("-Task", "ImportXml", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $workspace, "-AllowWrite") -Pattern "ImportXml requires -ExpectedProjectPath or -ExpectedProjectName" -TempRoot $tempRoot
        Expect-Failure -Name "SaveProject without evidence" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Compile evidence not found" -TempRoot $tempRoot
        Expect-Failure -Name "Disposable project prep without AllowCreate" -ScriptPath $DisposableProjectPrep -ScriptArgs @("-TargetRoot", $tempRoot, "-ProjectName", "Gate3PrepNoWrite") -Pattern "Creating a TIA project is a state-changing operation" -TempRoot $tempRoot
        $outsideTempRoot = Join-Path ([System.IO.Path]::GetPathRoot($env:TEMP)) "tia-harness-release-outside-temp"
        Expect-Failure -Name "Disposable project prep rejects non-TEMP TargetRoot" -ScriptPath $DisposableProjectPrep -ScriptArgs @("-AllowCreate", "-TargetRoot", $outsideTempRoot, "-ProjectName", "Gate3OutsideTemp") -Pattern "-TargetRoot must stay under the current TEMP directory" -TempRoot $tempRoot
        Expect-Failure -Name "Disposable project prep rejects dangerous ProjectName" -ScriptPath $DisposableProjectPrep -ScriptArgs @("-AllowCreate", "-TargetRoot", $tempRoot, "-ProjectName", "..") -Pattern "-ProjectName must not be '.' or '..'." -TempRoot $tempRoot
        Expect-Failure -Name "Disposable project prep rejects reserved DeviceName" -ScriptPath $DisposableProjectPrep -ScriptArgs @("-AllowCreate", "-TargetRoot", $tempRoot, "-ProjectName", "Gate3BadDevice", "-DeviceName", "CON") -Pattern "-DeviceName must not be a Windows reserved device name" -TempRoot $tempRoot
        Expect-Failure -Name "Disposable project prep rejects path separator BlockName" -ScriptPath $DisposableProjectPrep -ScriptArgs @("-AllowCreate", "-TargetRoot", $tempRoot, "-ProjectName", "Gate3BadBlock", "-BlockName", "Bad/Name") -Pattern "-BlockName must not contain path separators" -TempRoot $tempRoot

        $evidenceDir = Join-Path $workspace "evidence"
        New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
        $evidencePath = Join-Path $evidenceDir "last-compile.json"
        $fresh = (Get-Date).ToString("o")
        $old = (Get-Date).AddHours(-2).ToString("o")
        $future = (Get-Date).AddHours(2).ToString("o")

        ([ordered]@{ schemaVersion = 1; sourceTask = "CompilePlc"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects CompilePlc evidence" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence came from 'CompilePlc'" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects missing createdAt" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "missing createdAt" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $old; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects stale evidence" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence is stale" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $future; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects future evidence" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence is from the future" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 111111; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects tiaPid mismatch" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Compile evidence PID 111111 does not match requested PID 999999" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects missing processId" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "missing processId" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 111111; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects processId mismatch" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "processId 111111 does not match requested PID 999999" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects missing errorCount" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "missing errorCount" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 1; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects nonzero exitCode" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence is not clean" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $false; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects success false" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence is not clean" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 1 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects errorCount nonzero" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-AllowWrite") -Pattern "Last compile evidence is not clean" -TempRoot $tempRoot

        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        Expect-Failure -Name "SaveProject rejects custom evidence path" -ScriptPath $Runner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $workspace, "-CompileEvidencePath", $evidencePath, "-AllowWrite") -Pattern "-CompileEvidencePath is not accepted for save" -TempRoot $tempRoot
        Expect-Failure -Name "CompileEvidencePath outside evidence rejected" -ScriptPath $Runner -ScriptArgs @("-Task", "ImportXml", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $workspace, "-CompileEvidencePath", (Join-Path $tempRoot "outside.json"), "-AllowWrite") -Pattern "must stay under the current workspace evidence directory" -TempRoot $tempRoot

        $fakeHarness = Join-Path $tempRoot "fake-harness"
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeHarness "scripts") | Out-Null
        Copy-Item -LiteralPath $Runner -Destination (Join-Path $fakeHarness "scripts\Invoke-TiaV18LadHarness.ps1") -Force
        New-FakeCliExe -Path (Join-Path $fakeHarness "tools\bin\AiPlcTiaV18.exe")
        $fakeRunner = Join-Path $fakeHarness "scripts\Invoke-TiaV18LadHarness.ps1"

        $expectedMismatch = Invoke-ScriptForTest -ScriptPath $fakeRunner -ScriptArgs @("-Task", "ImportXml", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $workspace, "-ExpectedProjectPath", "C:\Temp\WrongProject.ap18", "-AllowWrite") -TempRoot $tempRoot
        if ($expectedMismatch.ExitCode -eq 0) {
            throw "Expected project path mismatch unexpectedly succeeded. Output: $($expectedMismatch.Text)"
        }
        if ($expectedMismatch.Text -notmatch "Expected project check failed") {
            throw "Expected project path mismatch failed with unexpected output: $($expectedMismatch.Text)"
        }
        if ($expectedMismatch.Text -match "import-xml") {
            throw "Expected project path mismatch reached import-xml unexpectedly: $($expectedMismatch.Text)"
        }
        if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
            throw "Expected project path mismatch left stale default save evidence behind: $evidencePath"
        }
        Write-Host "Expected failure OK: ExpectedProjectPath mismatch stops before import"

        $customWorkspace = Join-Path $tempRoot "custom-workspace"
        $customEvidenceDir = Join-Path $customWorkspace "evidence"
        New-Item -ItemType Directory -Force -Path $customEvidenceDir | Out-Null
        $customDefaultEvidence = Join-Path $customEvidenceDir "last-compile.json"
        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $customDefaultEvidence -Encoding UTF8

        Expect-Success -Name "ImportCompile with custom evidence clears default save evidence" -ScriptPath $fakeRunner -ScriptArgs @("-Task", "ImportCompile", "-Pid", "999999", "-XmlPath", $xml, "-Kind", "block", "-Workspace", $customWorkspace, "-CompileEvidencePath", "custom.json", "-ExpectedProjectPath", "C:\Temp\FakeProject.ap18", "-ExpectedProjectName", "FakeProject", "-AllowWrite") -TempRoot $tempRoot | Out-Null
        if (Test-Path -LiteralPath $customDefaultEvidence -PathType Leaf) {
            throw "Custom evidence import left stale default save evidence behind: $customDefaultEvidence"
        }
        Assert-FileExists -Path (Join-Path $customEvidenceDir "custom.json") -Description "custom compile evidence"
        Expect-Failure -Name "SaveProject ignores custom evidence and rejects missing default evidence" -ScriptPath $fakeRunner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $customWorkspace, "-AllowWrite") -Pattern "Compile evidence not found" -TempRoot $tempRoot

        $failureWorkspace = Join-Path $tempRoot "failure-workspace"
        $failureEvidenceDir = Join-Path $failureWorkspace "evidence"
        New-Item -ItemType Directory -Force -Path $failureEvidenceDir | Out-Null
        $failureEvidence = Join-Path $failureEvidenceDir "last-compile.json"
        $failXml = Join-Path $tempRoot "fail.xml"
        Set-Content -LiteralPath $failXml -Encoding UTF8 -Value "<root />"
        ([ordered]@{ schemaVersion = 1; sourceTask = "ImportCompile"; createdAt = $fresh; tiaPid = 999999; processId = 999999; exitCode = 0; compile = [ordered]@{ success = $true; errorCount = 0 } } | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $failureEvidence -Encoding UTF8
        Expect-Failure -Name "Failed ImportCompile replaces stale save evidence" -ScriptPath $fakeRunner -ScriptArgs @("-Task", "ImportCompile", "-Pid", "999999", "-XmlPath", $failXml, "-Kind", "block", "-Workspace", $failureWorkspace, "-ExpectedProjectPath", "C:\Temp\FakeProject.ap18", "-ExpectedProjectName", "FakeProject", "-AllowWrite") -Pattern "ImportCompile failed with exit code 2" -TempRoot $tempRoot -MayReachCli
        Expect-Failure -Name "SaveProject rejects failed import compile evidence" -ScriptPath $fakeRunner -ScriptArgs @("-Task", "SaveProject", "-Pid", "999999", "-Workspace", $failureWorkspace, "-AllowWrite") -Pattern "Last compile evidence is not clean" -TempRoot $tempRoot
    } finally {
        Remove-TempDir -Path $tempRoot
    }
}

function Test-LivePreflight {
    Write-Host "Checking live validator write-intent preflight..."
    $tempRoot = New-TempDir -Prefix "tia-harness-release-live-preflight"
    try {
        $xml = Join-Path $tempRoot "dummy.xml"
        Set-Content -LiteralPath $xml -Encoding UTF8 -Value "<root />"
        $live = Join-Path $ScriptRoot "Test-HarnessLiveRoundTrip.ps1"
        Expect-Failure -Name "SelfImport without AllowWrite" -ScriptPath $live -ScriptArgs @("-Workspace", $tempRoot, "-SelfImportExportedXml") -Pattern "-SelfImportExportedXml and -PatchedXmlPath are write intents" -TempRoot $tempRoot
        Expect-Failure -Name "PatchedXmlPath without AllowWrite" -ScriptPath $live -ScriptArgs @("-Workspace", $tempRoot, "-PatchedXmlPath", $xml) -Pattern "-SelfImportExportedXml and -PatchedXmlPath are write intents" -TempRoot $tempRoot
        Expect-Failure -Name "Save without AllowWrite" -ScriptPath $live -ScriptArgs @("-Workspace", $tempRoot, "-Save") -Pattern "-Save requires -AllowWrite" -TempRoot $tempRoot
        Expect-Failure -Name "Save without write input" -ScriptPath $live -ScriptArgs @("-Workspace", $tempRoot, "-Save", "-AllowWrite") -Pattern "-Save requires -SelfImportExportedXml or -PatchedXmlPath" -TempRoot $tempRoot
    } finally {
        Remove-TempDir -Path $tempRoot
    }
}

function Test-InstallerPortability {
    if ($SkipInstall) {
        Write-Host "Skipping installer portability test."
        return
    }

    Write-Host "Checking installer portability and path safety..."
    $tempRoot = New-TempDir -Prefix "tia-harness-release-install"
    try {
        Expect-Failure -Name "Dangerous HarnessName rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", ".", "-Force") -Pattern "-HarnessName must not be '.' or '..'." -TempRoot $tempRoot
        Expect-Failure -Name "Reserved HarnessName CON rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", "CON", "-Force") -Pattern "Windows reserved device name" -TempRoot $tempRoot
        Expect-Failure -Name "Reserved HarnessName NUL rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", "NUL", "-Force") -Pattern "Windows reserved device name" -TempRoot $tempRoot
        Expect-Failure -Name "Reserved HarnessName COM1 rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", "COM1", "-Force") -Pattern "Windows reserved device name" -TempRoot $tempRoot
        Expect-Failure -Name "Trailing dot HarnessName rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", "bad.", "-Force") -Pattern "must not end with a dot or space" -TempRoot $tempRoot
        Expect-Failure -Name "Trailing space HarnessName rejected" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $tempRoot, "-HarnessName", "bad ", "-Force") -Pattern "must not end with a dot or space" -TempRoot $tempRoot

        $nonHarnessRoot = New-TempDir -Prefix "tia-harness-release-install-nonharness"
        try {
            $nonHarness = Join-Path $nonHarnessRoot "tia-v18-lad-agent"
            New-Item -ItemType Directory -Force -Path $nonHarness | Out-Null
            Set-Content -LiteralPath (Join-Path $nonHarness "note.txt") -Encoding UTF8 -Value "not a harness"
            Expect-Failure -Name "Force refuses non-harness destination" -ScriptPath $Installer -ScriptArgs @("-TargetRoot", $nonHarnessRoot, "-Force") -Pattern "does not look like a harness" -TempRoot $tempRoot
        } finally {
            Remove-TempDir -Path $nonHarnessRoot
        }

        & powershell -ExecutionPolicy Bypass -File $Installer -TargetRoot $tempRoot
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        $installed = Join-Path $tempRoot "tia-v18-lad-agent"
        foreach ($relative in @(
            "AGENTS.md",
            "harness.json",
            "tools\bin\AiPlcTiaV18.exe",
            "tools\bin\AiPlcTiaV18.Core.dll",
            ".cursor\rules\tia-v18-lad-agent.mdc",
            ".continue\rules\tia-v18-lad-harness.md",
            ".devin\rules\tia-v18-lad-harness.md"
        )) {
            Assert-FileExists -Path (Join-Path $installed $relative) -Description "installed harness file"
        }

        foreach ($relative in @(
            ".aider.conf.yml",
            "AGENTS.md",
            "AIDER.md",
            "CLAUDE.md",
            "CONVENTIONS.md",
            "GEMINI.md",
            "COPILOT.md",
            "KILO.md",
            "ROO.md",
            "CONTINUE.md",
            ".cursorrules",
            ".github\copilot-instructions.md",
            ".github\instructions\tia-v18-lad.instructions.md",
            ".cursor\rules\tia-v18-lad-agent.mdc",
            ".kilo\rules\tia-v18-lad-harness.md",
            ".kilocode\rules.md",
            ".kilocode\rules\tia-v18-lad-harness.md",
            ".roo\rules.md",
            ".roo\rules\tia-v18-lad-harness.md",
            ".roorules",
            ".windsurfrules",
            ".windsurf\rules\tia-v18-lad-harness.md",
            ".continue\rules.md",
            ".continue\rules\tia-v18-lad-harness.md",
            ".devin\rules\tia-v18-lad-harness.md",
            ".clinerules\tia-v18-lad-harness.md"
        )) {
            Assert-FileExists -Path (Join-Path $tempRoot $relative) -Description "project-root pointer"
        }
        $aiderRootConfig = Get-Content -LiteralPath (Join-Path $tempRoot ".aider.conf.yml") -Raw -Encoding UTF8
        if (($aiderRootConfig -notmatch "read:") -or ($aiderRootConfig -notmatch "tia-v18-lad-agent/AGENTS.md")) {
            throw "Project-root .aider.conf.yml does not point Aider at the installed harness."
        }

        & powershell -ExecutionPolicy Bypass -File (Join-Path $installed "scripts\Test-HarnessOffline.ps1")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

        $sentinelRoot = New-TempDir -Prefix "tia-harness-release-install-pointers"
        try {
            $sentinelPointer = Join-Path $sentinelRoot "AGENTS.md"
            Set-Content -LiteralPath $sentinelPointer -Encoding UTF8 -Value "sentinel"
            & powershell -ExecutionPolicy Bypass -File $Installer -TargetRoot $sentinelRoot
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $sentinelContent = Get-Content -LiteralPath $sentinelPointer -Raw -Encoding UTF8
            if ($sentinelContent.Trim() -ne "sentinel") {
                throw "Installer overwrote an existing project-root pointer without -ForceAgentPointers."
            }

            & powershell -ExecutionPolicy Bypass -File $Installer -TargetRoot $sentinelRoot -Force -ForceAgentPointers
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            $forcedContent = Get-Content -LiteralPath $sentinelPointer -Raw -Encoding UTF8
            if (($forcedContent -notmatch [regex]::Escape("-AllowWrite")) -or ($forcedContent -notmatch [regex]::Escape("docs/validation-gates.md"))) {
                throw "Forced project-root pointer does not include the write gate and validation docs."
            }
        } finally {
            Remove-TempDir -Path $sentinelRoot
        }
    } finally {
        Remove-TempDir -Path $tempRoot
    }
}

function Resolve-ZipPath {
    if (-not [string]::IsNullOrWhiteSpace($ZipPath)) {
        return (Resolve-Path -LiteralPath $ZipPath).Path
    }

    $candidate = Join-Path (Split-Path -Parent $HarnessRoot) ($HarnessName + ".zip")
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    return ""
}

function Test-ZipPackage {
    if ($SkipZip) {
        Write-Host "Skipping zip validation."
        return
    }

    $resolvedZip = Resolve-ZipPath
    if ([string]::IsNullOrWhiteSpace($resolvedZip)) {
        Write-Host "Zip validation skipped: no zip path supplied and default zip was not found."
        return
    }

    Write-Host "Checking zip package: $resolvedZip"
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $prefix = $HarnessName + "/"
    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        $nonPrefixed = @($names | Where-Object { $_ -ne $prefix -and -not $_.StartsWith($prefix, [System.StringComparison]::Ordinal) })
        if ($nonPrefixed.Count -gt 0) {
            throw "Zip contains entries outside top-level $prefix : $($nonPrefixed -join ', ')"
        }

        $required = @(
            ".aider.conf.yml",
            ".cursorrules",
            ".cursor/rules/tia-v18-lad-agent.mdc",
            ".continue/rules/tia-v18-lad-harness.md",
            ".devin/rules/tia-v18-lad-harness.md",
            ".github/copilot-instructions.md",
            ".github/instructions/tia-v18-lad.instructions.md",
            "AGENTS.md",
            "CONVENTIONS.md",
            "harness.json",
            "scripts/Test-HarnessRelease.ps1",
            "scripts/New-TiaV18DisposableLadProject.ps1",
            "scripts/Test-HarnessLiveRoundTrip.ps1",
            "scripts/Invoke-TiaV18LadHarness.ps1",
            "tools/bin/AiPlcTiaV18.exe",
            "tools/bin/AiPlcTiaV18.Core.dll",
            "workspace/README.md"
        ) | ForEach-Object { $prefix + $_ }
        $missing = @($required | Where-Object { $names -notcontains $_ })
        if ($missing.Count -gt 0) {
            throw "Zip is missing required entries: $($missing -join ', ')"
        }

        $forbidden = @($names | Where-Object { $_ -match 'AiPlcTiaV18\.Core\.Tests\.exe$|workspace/(exports|patched|reports|evidence)/[^/]+$|\.pdb$|(^|/)obj/|(^|/)artifacts/|(^|/)TestResults/|(^|/)\.git/' })
        if ($forbidden.Count -gt 0) {
            throw "Zip contains forbidden entries: $($forbidden -join ', ')"
        }
    } finally {
        $zip.Dispose()
    }

    $tempRoot = New-TempDir -Prefix "tia-harness-release-zip"
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($resolvedZip, $tempRoot)
        $extractedHarness = Join-Path $tempRoot $HarnessName
        & powershell -ExecutionPolicy Bypass -File (Join-Path $extractedHarness "scripts\Test-HarnessOffline.ps1")
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Remove-TempDir -Path $tempRoot
    }
}

Write-Host "=== Release validation: offline package ==="
& powershell -ExecutionPolicy Bypass -File $OfflineValidator
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Test-SafetyGuards
Test-LivePreflight
Test-InstallerPortability
Test-ZipPackage

Write-Host "TIA V18 LAD agent harness release validation passed."
