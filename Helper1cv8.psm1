if (-not (Get-Command "1cv8" -ErrorAction SilentlyContinue)) {
    $errorMessage = "'1cv8' not found in PATH. Install 1C:Enterprice and add it to PATH."
    Write-Error -Message $errorMessage -Category ResourceUnavailable
    throw $errorMessage  # Прерываем загрузку модуля
}

function Get-UniqueLogName {
    $length = 8
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $random = -join ((Get-Random -Count $length -InputObject $chars.ToCharArray()) | Sort-Object { Get-Random })
    return $random
}

function Get-MaxVersionPath {
	param (
        [string]$directoryPath
    )

	$subdirectories = Get-ChildItem -Path $directoryPath -Directory

	$maxVersion = ""
	$maxVersionPath = ""
	
	foreach ($subdir in $subdirectories) {
		$version = $subdir.Name
		if ($version -match '^\d+\.\d+\.\d+\.\d+$') {
			if ($maxVersion -eq "" -or (Compare-Versions -version1 $version -version2 $maxVersion)) {
				$maxVersion = $version
				$maxVersionPath = $subdir.FullName
			}
		}
	}

	return $maxVersionPath

}

function Compare-Versions {
    param (
        [string]$version1,
        [string]$version2
    )

    $v1 = $version1 -split '\.'
    $v2 = $version2 -split '\.'

    for ($i = 0; $i -lt [math]::max($v1.Length, $v2.Length); $i++) {
        $num1 = if ($i -lt $v1.Length) { [int]$v1[$i] } else { 0 }
        $num2 = if ($i -lt $v2.Length) { [int]$v2[$i] } else { 0 }

        if ($num1 -ne $num2) {
            return $num1 -gt $num2
        }
    }

    return $false
}

function Update-OnecBasesFromCfu {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName,
        [string]$cfusPath
    )
    
    Write-Host "Update base $ibServer\$ibName from $cfusPath" -ForegroundColor Yellow

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    $updatesPath = Join-Path -Path $cfusPath -ChildPath "$ibName"
    $maxVersionPath = Get-MaxVersionPath -directoryPath $updatesPath
    $lastUpdatePath = Join-Path -Path $maxVersionPath -ChildPath "1cv8.cfu"

    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $dbms = $ibServerConfig.serverType
    if ($dbms -eq "file") {
        $dbPath = $ibConfig.path
        $updateArgs = @("DESIGNER",
            "/F `"$dbPath`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/UpdateCfg `"$lastUpdatePath`"",
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }
    else {
        $ibServer = $ibServerConfig.server
        $ibName = $ibConfig.name
        $updateArgs = @("DESIGNER",
            "/S `"$ibServer\$ibName`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/UpdateCfg `"$lastUpdatePath`"",
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }

    Start-Process "1cv8" -ArgumentList $updateArgs -NoNewWindow -Wait
    Write-Host "Now database $ibServer\$ibName updated to $maxVersionPath" -ForegroundColor Yellow
    
}

function Update-DBCfg {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName,
        [string]$logFile
    )

    Write-Host "Appling saved config in $ibServer\$ibName to infobase config" -ForegroundColor Yellow

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    $dbms = $ibServerConfig.serverType
    if ($dbms -eq "file") {
        $dbPath = $ibConfig.path
        $importArgs = @("DESIGNER",
            "/F `"$dbPath`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/UpdateDBCfg",
            "/UC 0000",
            "/Out `"$logFile`"", "-NoTruncate"
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }
    else {
        $ibServer = $ibServerConfig.server
        $ibName = $ibConfig.name
        $importArgs = @("DESIGNER",
            "/S `"$ibServer\$ibName`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/UpdateDBCfg", "-Server", "-v2",
            "/UC 0000",
            "/Out `"$logFile`"", "-NoTruncate"
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }

    Start-Process "1cv8" -ArgumentList $importArgs -NoNewWindow -Wait
    Write-Host "Saved config applied for $ibServer\$ibName" -ForegroundColor Yellow
}

function Update-ibData {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName
    )

    Write-Host "Updating infobase data $ibServer\$ibName" -ForegroundColor Yellow

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    $dbms = $ibServerConfig.serverType
    $cCommand = "ВыполнитьОбновлениеИЗавершитьРаботу"
    if ($dbms -eq "file") {
        $dbPath = $ibConfig.path
        $importArgs = @("ENTERPRISE",
            "/F `"$dbPath`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/C `"$cCommand`"",
            "/UC 0000",
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }
    else {
        $ibServer = $ibServerConfig.server
        $ibName = $ibConfig.name
        $importArgs = @("ENTERPRISE",
            "/S `"$ibServer\$ibName`"",
            "/N `"$ibUser`"", "/P `"$ibPassword`"",
            "/C `"$cCommand`"",
            "/UC 0000",
            "/DisableStartupDialogs", "/DisableStartupMessages")
    }

    Start-Process "1cv8c" -ArgumentList $importArgs -NoNewWindow  -Wait
    Write-Host "Update infobase data finish $ibServer\$ibName" -ForegroundColor Yellow
}