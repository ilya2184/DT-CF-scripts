function Get-MainConfig {
	param (
		[string]$mainConfigPath
	)

    $mainConfig = Get-Content $mainConfigPath | ConvertFrom-Json

	return $mainConfig
}

function Get-ServerConfig {
	param (
		[pscustomobject[]]$mainConfig,
		[string]$server
	)

    $foundConfigs = $mainConfig | Where-Object {
            $_.server -eq $server
        }
     
    if (-not $foundConfigs) {
        throw "There is no config for server = '$server'."
    }

	$foundConfig = $foundConfigs | Select-Object -First 1

	return $foundConfig
}

function Get-LoginFromConfig {
    param (
		[pscustomobject]$serverConfig,
        [string]$loginType
    )

    $foundLogins = $serverConfig.logintypes | Where-Object {
        $_.loginType -eq $loginType
    }

    if (-not $foundLogins) {
        $serverName = $serverConfig.server
        throw "There is no login = '$loginType' in server = '$serverName'."
    }

	$foundLogin = $foundLogins | Select-Object -First 1

	return $foundLogin

}

function Get-DataBaseConfig {
	param (
		[pscustomobject]$serverConfig,
		[string]$baseName
	)


    $foundBases = $serverConfig.databases | Where-Object {
        $_.name -eq $baseName
    }

    if (-not $foundBases) {
        $serverName = $serverConfig.server
        throw "There is no config server = '$serverName', database name = '$baseName'."
    }

	$foundBase = $foundBases | Select-Object -First 1

	return $foundBase
}
