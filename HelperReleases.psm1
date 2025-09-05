function Get-LatestReleasePath {
	param (
		[string]$releasesPath,
		[string]$internal
	)
	
	$directoryPath = Join-Path -Path $releasesPath -ChildPath "$internal"
	
	# Находим последний по дате файл с расширением .cf
	$latestFile = Get-ChildItem -Path $directoryPath -Filter "*.cf" | 
				  Sort-Object LastWriteTime -Descending | 
				  Select-Object -First 1
	
	if (-not ($latestFile)) {
		throw "CF not found in $directoryPath"
	}
		
	return $($latestFile.FullName)
}


function Publish-GenericPackageToGLRegistry {
	param (
		[pscustomobject[]]$mainConfig,
		[string]$gLServer,
		[string]$prName,
		[string]$FilePath,
		[string]$PackageName,
		[string]$PackageVersion
	)


	# Получаем конфиг сервера GitLab/Registry
	$serverConfig = Get-ServerConfig -mainConfig $mainConfig -server $gLServer

	$login = Get-LoginFromConfig -serverConfig $serverConfig -loginType "registry"
	$token = [string]$login.password

	# Базовый URL для обращений к GitLab API
	$baseUrl = $gLServer.TrimEnd('/')

	# Находим описание проекта в databases по имени
	$projectConfig = Get-DataBaseConfig -serverConfig $serverConfig -baseName $prName

	# Определяем идентификатор проекта из свойства 'internal' записи databases
	$projectId = [string]$projectConfig.internal

	# URL загрузки
	$fileName = [System.IO.Path]::GetFileName($FilePath)
	$uri = "$baseUrl/api/v4/projects/$projectId/packages/generic/$PackageName/$PackageVersion/1cv8.cf"

	# Выполняем загрузку через Native PowerShell (Invoke-WebRequest PUT)
	$headers = @{ 'PRIVATE-TOKEN' = $token }
	Write-Host "Uploading '$fileName' to registry: $uri" -ForegroundColor Yellow
	$response = Invoke-WebRequest `
		-Uri $uri -Method Put -Headers $headers `
		-InFile $FilePath -ContentType 'application/octet-stream' -UseBasicParsing
	return $response
}