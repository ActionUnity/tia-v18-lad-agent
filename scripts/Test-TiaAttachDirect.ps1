param(
    [int]$ProcessId = 0,
    [switch]$ListOnly
)

$ErrorActionPreference = "Stop"

$apiDir = "C:\Program Files\Siemens\Automation\Portal V18\PublicAPI\V18"
$apiDll = Join-Path $apiDir "Siemens.Engineering.dll"

if (-not (Test-Path $apiDll)) {
    throw "Openness API not found: $apiDll"
}

# Resolve dependencies from the PublicAPI directory
$script:TiaResolvingAssemblies = @{}
$OnAssemblyResolve = [System.ResolveEventHandler] {
    param($sender, $args)
    if ([string]::IsNullOrWhiteSpace($args.Name)) {
        return $null
    }
    $name = [System.Reflection.AssemblyName]::new($args.Name)
    foreach ($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        if ($assembly.GetName().Name -ieq $name.Name) {
            return $assembly
        }
    }
    if ($script:TiaResolvingAssemblies.ContainsKey($name.Name)) {
        return $null
    }
    $probe = Join-Path $apiDir "$($name.Name).dll"
    if (Test-Path $probe) {
        try {
            $script:TiaResolvingAssemblies[$name.Name] = $true
            return [System.Reflection.Assembly]::LoadFrom($probe)
        } finally {
            $script:TiaResolvingAssemblies.Remove($name.Name)
        }
    }
    return $null
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($OnAssemblyResolve)

[System.Reflection.Assembly]::LoadFrom($apiDll) | Out-Null
Write-Host "Openness API loaded."

Write-Host "TIA Portal processes:"
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    Write-Host "  PID=$($p.Id) Path=$($p.Path) Project=$($p.ProjectPath) Mode=$($p.Mode)"
}

if ($ListOnly) {
    Write-Host "ListOnly requested; skipping attach."
    exit 0
}

if ($ProcessId -le 0) {
    throw "-ProcessId is required unless -ListOnly is used."
}

$process = $null
foreach ($p in [Siemens.Engineering.TiaPortal]::GetProcesses()) {
    if ($p.Id -eq $ProcessId) {
        $process = $p
        break
    }
}
if (-not $process) {
    throw "Process $ProcessId not found"
}

Write-Host "Attempting attach to PID $ProcessId..."
try {
    $portal = $process.Attach()
    Write-Host "Attach succeeded!"

    $projects = $portal.Projects
    foreach ($proj in $projects) {
        Write-Host "Project: $($proj.Name) Path=$($proj.Path)"
        foreach ($dev in $proj.Devices) {
            Write-Host "  Device: $($dev.Name)"
            foreach ($item in $dev.DeviceItems) {
                Write-Host "    DeviceItem: $($item.Name)"
                try {
                    $sc = $item.GetService([Siemens.Engineering.HW.Features.SoftwareContainer])
                    if ($sc) {
                        $sw = $sc.Software
                        if ($sw -is [Siemens.Engineering.SW.PlcSoftware]) {
                            Write-Host "      PLC Software: $($sw.Name)"
                            $bg = $sw.BlockGroup
                            Write-Host "        BlockGroup count: $($bg.Blocks.Count)"
                            foreach ($b in $bg.Blocks) {
                                Write-Host "        Block: $($b.Name) ($($b.ProgrammingLanguage))"
                            }
                            foreach ($g in $bg.Groups) {
                                Write-Host "        Group: $($g.Name)"
                                foreach ($b in $g.Blocks) {
                                    Write-Host "          Block: $($b.Name) ($($b.ProgrammingLanguage))"
                                }
                            }
                        } elseif ($sw -is [System.Collections.IEnumerable]) {
                            foreach ($s in $sw) {
                                if ($s -is [Siemens.Engineering.SW.PlcSoftware]) {
                                    Write-Host "      PLC Software: $($s.Name)"
                                }
                            }
                        }
                    }
                } catch {
                    Write-Host "    Skipped $($item.Name): $($_.Exception.Message)"
                }
            }
        }
    }

    $portal.Dispose()
    Write-Host "Done."
} catch {
    Write-Host "ATTACH FAILED: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    if ($_.Exception.InnerException) {
        Write-Host "  Inner: $($_.Exception.InnerException.Message)"
    }
    exit 1
}
