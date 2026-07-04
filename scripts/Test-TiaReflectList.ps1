param()

$ErrorActionPreference = "Stop"

$apiDir = "C:\Program Files\Siemens\Automation\Portal V18\PublicAPI\V18"
$apiDll = Join-Path $apiDir "Siemens.Engineering.dll"
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

$assembly = [System.Reflection.Assembly]::LoadFrom($apiDll)
$type = $assembly.GetType("Siemens.Engineering.TiaPortal")
$method = $type.GetMethod("GetProcesses", [Type[]]@())
$processes = $method.Invoke($null, @())
$items = @($processes)

Write-Host "Apartment=$([System.Threading.Thread]::CurrentThread.GetApartmentState())"
Write-Host "ReturnType=$($processes.GetType().FullName)"
Write-Host "Count=$($items.Count)"
foreach ($process in $items) {
    Write-Host "PID=$($process.Id) Project=$($process.ProjectPath) Mode=$($process.Mode)"
}
