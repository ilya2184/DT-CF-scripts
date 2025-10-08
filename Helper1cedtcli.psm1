if (-not (Get-Command "1cedtcli" -ErrorAction SilentlyContinue)) {
    $errorMessage = "'1cedtcli' not found in PATH. Install 1C:EDT and add it to PATH."
    Write-Error -Message $errorMessage -Category ResourceUnavailable
    throw $errorMessage  # Прерываем загрузку модуля
}

function Get-UniqueProjectName {
    $length = 8
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $random = -join ((Get-Random -Count $length -InputObject $chars.ToCharArray()) | Sort-Object {Get-Random})
    return $random
}

function Get-ConfigVersionFromEDTsrc {
    param (
        [string]$projectSrc
    )
    
    [xml]$configInfo = Get-Content -Path (Join-Path -Path $projectSrc -ChildPath "Configuration/Configuration.mdo")
    [string]$configVersion = $configInfo.Configuration.Version

    return $configVersion

}

function Update-WorkSpaceFromXML {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName,
        [string]$xmlPath
    )
    
    Write-Host "Import from 1c-xml $xmlPath to $ibServer\$ibName workspace" -ForegroundColor Yellow

    $projecName = Get-UniqueProjectName
    $serverConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibConfig = Get-DataBaseConfig -serverConfig $serverConfig -baseName $ibName
    $edtWorkspace = $ibConfig.workspace
    $tempProjectPath = Join-Path -Path $edtWorkspace -ChildPath $projecName
    $importArgs = @("-data", $edtWorkspace,
        "-vmargs", "-Xmx8g",
        "-command", "import",
        "--configuration-files", "`"$xmlPath`"",
        "--project", "`"$tempProjectPath`"")
    
    Start-Process "1cedtcli" -ArgumentList $importArgs -NoNewWindow -Wait
    
    $ibConfig = Get-DataBaseConfig -serverConfig $serverConfig -baseName $ibName
    $gitPath = Join-Path -Path $edtWorkspace -ChildPath "$($ibConfig.gitname)"

    Write-Host "  Setting sonar.projectVersion from 1c-xml $xmlPath to $gitPath" -ForegroundColor DarkYellow
    $tempProjectSrc = Join-Path -Path $tempProjectPath -ChildPath "src"
    $configVersion = Get-ConfigVersionFromEDTsrc -projectSrc $tempProjectSrc
    $sonarProperiesPath = Join-Path -Path $gitPath -ChildPath "sonar-project.properties"
    if (Test-Path $sonarProperiesPath) {
        $sonarProperies = Get-Content -Path $sonarProperiesPath
        $sonarProperies = $sonarProperies -replace 'sonar\.projectVersion=.*', "sonar.projectVersion=$configVersion"
        Set-Content -Path $sonarProperiesPath -Value $sonarProperies
    } else {
        Write-Warning "File $sonarProperiesPath not found. Skipping sonar.projectVersion update."
    }
    
    Write-Host "  Remove old src edt-xml" -ForegroundColor DarkYellow
    
    $projectSrc = Join-Path -Path (Join-Path -Path $gitPath -ChildPath "$($ibConfig.project)") -ChildPath "src"
    Remove-Item -Path $projectSrc -Recurse -Force
    
    Write-Host "  Move new src ext-xml" -ForegroundColor Yellow
    
    Move-Item -Path $tempProjectSrc -Destination $projectSrc
    
    Write-Host "  Remove temp project $projecName from workspace" -ForegroundColor DarkYellow
    $deleteArgs = @("-data", $edtWorkspace,
        "-command", "delete", "--yes"
        "[$projecName]")
    Start-Process "1cedtcli" -ArgumentList $deleteArgs -NoNewWindow -Wait
    
    Write-Host "  Remove temp project files $tempProjectPath" -ForegroundColor DarkYellow
    Remove-Item -Path $tempProjectPath -Recurse -Force
    
    Write-Host "Project $gitPath updated to $configVersion" -ForegroundColor Yellow
    return $gitPath
}

function Export-ProjectTo1cXML {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$glServer,
        [string]$glName,
        [string]$edtWorkspace,
        [string]$gitPath
    )
    
    Write-Host "Export from $glServer/$glName to 1c-xml" -ForegroundColor Yellow

    $glServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $glServer
    $glBaseConfig = Get-DataBaseConfig -serverConfig $glServerConfig -baseName $glName
    $projectPath = Join-Path -Path $gitPath -ChildPath ($glBaseConfig.project)

    $ProjectSrc = Join-Path -Path $ProjectPath -ChildPath "src"
    $configVersion = Get-ConfigVersionFromEDTsrc -projectSrc $ProjectSrc

    $xmlPath = Join-Path -Path $Env:TEMP -ChildPath $configVersion
    if (Test-Path $xmlPath) {Remove-Item $xmlPath -Recurse -Force}

    $exportArgs = @("-data", "`"$edtWorkspace`"",
        "-command", "export",
        "--project", "`"$projectPath`"",
        "--configuration-files", "`"$xmlPath`"")
    
    Start-Process "1cedtcli" -ArgumentList $exportArgs -NoNewWindow -Wait
    
    $zipPath = Join-Path -Path $Env:TEMP -ChildPath ($configVersion + ".zip")
    if (Test-Path $zipPath) {Remove-Item $zipPath -Recurse -Force}
    
    Compress-Archive -Path $xmlPath -DestinationPath $zipPath
    Remove-Item $xmlPath -Recurse -Force
    Write-Host "Now we have $glServer/$glName 1C-XML-ZIP $zipPath, $edtWorkspace mybe updated" -ForegroundColor Yellow

    return $zipPath
}