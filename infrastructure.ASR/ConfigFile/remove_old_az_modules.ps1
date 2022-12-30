foreach ($module in (Get-Module -ListAvailable Az*).Name |Get-Unique) {
    if ((Get-Module -ListAvailable $module).Count -gt 1) {
    $Latest_Version = (Get-Module -ListAvailable $module | Select-Object Version | Sort-Object Version)[-1]
    write-host "Latest $module version $Latest_Version"
    Get-Module -ListAvailable $module | Where-Object {$_.Version -ne $Latest_Version.Version} | ForEach-Object {Uninstall-Module -Name $_.Name -RequiredVersion $_.Version -verbose}
    }
    else {
    Write-Output "Only one version installed for $module"
    }
    }