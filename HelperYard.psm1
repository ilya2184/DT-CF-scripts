if (-not (Get-Command "rac" -ErrorAction SilentlyContinue)) {
    $errorMessage = "'rac' not found in PATH. Install 1C:Enterprice server administative components and add it to PATH."
    Write-Error -Message $errorMessage -Category ResourceUnavailable
    throw $errorMessage  # Прерываем загрузку модуля
}
function Get-UniqueConfigName {
    $length = 8
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    [string]$random = -join ((Get-Random -Count $length -InputObject $chars.ToCharArray()) | Sort-Object {Get-Random})
    return $random + ".json"
}

function Get-UpdatesFromSite {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$yardTemplatesPath,
        [string]$yardTemplateName
    )
    $onecReleasesServer = "https://its.1c.ru"
    $yardWorkingPath = $Env:TEMP
    Write-Host "Get updates of '$yardTemplateName'" -ForegroundColor Yellow

    # Create YARD config
    $yardConfigContent = Get-Content (Join-Path $yardTemplatesPath "$yardTemplateName.json")

    $serverConfig = Get-ServerConfig -mainConfig $mainConfig -server $onecReleasesServer
    $itsCredentials = Get-LoginFromConfig -serverConfig $serverConfig -loginType "admin"
    $yardConfigContent = $yardConfigContent -replace '\$itsUser', $itsCredentials.user
    $yardConfigContent = $yardConfigContent -replace '\$itsPassword', $itsCredentials.password

    $yardConfigPath = Join-Path $Env:TEMP (Get-UniqueConfigName + ".json")
    Set-Content $yardConfigPath $yardConfigContent
    # Create YARD config finish

    $yardWorkspace = Get-WorkspaceForInternal -serverConfig $serverConfig -internal $yardTemplateName

    $yardArgs = @("process",
        "--work-dir `"$yardWorkspace`"", "`"$yardConfigPath`"")
    Start-Process "yard" -ArgumentList $yardArgs -WorkingDirectory $yardWorkingPath -NoNewWindow -wait
    Remove-Item -Path "$yardConfigPath" -Recurse -Force
    
    Write-Host "Now we have updates of '$yardTemplateName' in '$yardWorkspace'" -ForegroundColor Yellow
    return $yardWorkspace
}