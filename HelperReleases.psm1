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
	$headers = @{ 'DEPLOY-TOKEN' = $token }
	Write-Host "Uploading '$fileName' to registry: $uri" -ForegroundColor Yellow
	$response = Invoke-WebRequest `
		-Uri $uri -Method Put -Headers $headers `
		-InFile $FilePath -ContentType 'application/octet-stream' -UseBasicParsing
	return $response
}

function Get-LatestGenericPackageFromGLRegistry {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$gLServer,
        [string]$prName,
        [string]$PackageName,
        [string]$releasePath
    )

    # Получаем конфиг сервера GitLab/Registry
    $serverConfig = Get-ServerConfig -mainConfig $mainConfig -server $gLServer

    $login = Get-LoginFromConfig -serverConfig $serverConfig -loginType "private"
    $token = [string]$login.password

    # Базовый URL для обращений к GitLab API
    $baseUrl = $gLServer.TrimEnd('/')

    # Находим описание проекта в databases по имени
    $projectConfig = Get-DataBaseConfig -serverConfig $serverConfig -baseName $prName

    # Определяем идентификатор проекта из свойства 'internal' записи databases
    $projectId = [string]$projectConfig.internal

    # Получаем список всех пакетов в Generic реестре
    $uri = "$baseUrl/api/v4/projects/$projectId/packages?package_name=$PackageName&sort=desc&per_page=1"
    $headers = @{ 'PRIVATE-TOKEN' = $token }
    
    Write-Host "Getting package list from registry: $uri" -ForegroundColor Yellow
    $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $headers -UseBasicParsing
    $packages = $response.Content | ConvertFrom-Json

    if (-not $packages -or $packages.Count -eq 0) {
        Write-Host "No packages found in registry" -ForegroundColor Red
        return $null
    }

    # Сортируем пакеты по дате создания (от новых к старым)
    $sortedPackages = $packages | Sort-Object -Property created_at -Descending
    
    # Перебираем пакеты в порядке от нового к старому
    foreach ($package in $sortedPackages) {
        $packageVersion = $package.version
        
        # Пытаемся напрямую скачать файл "1cv8.cf"
        $downloadUri = "$baseUrl/api/v4/projects/$projectId/packages/generic/$PackageName/$packageVersion/1cv8.cf"
        
        try {
            Write-Host "Trying to get '1cv8.cf' from version: $packageVersion" -ForegroundColor Gray
            # Пробуем сделать HEAD запрос для проверки существования файла
            $testResponse = Invoke-WebRequest -Uri $downloadUri -Method Head -Headers $headers -UseBasicParsing -ErrorAction SilentlyContinue
            
            if ($testResponse.StatusCode -eq 200) {
                Write-Host "Found '1cv8.cf' in version: $packageVersion" -ForegroundColor Green
                # Файл существует, сохраняем информацию для скачивания
                $foundPackage = @{
                    Package = $package
                    Version = $packageVersion
                    DownloadUri = $downloadUri
                }
                break
            }
        }
        catch {
            # Если файла нет, продолжаем искать в следующем пакете
            Write-Host "File '1cv8.cf' not found in version $packageVersion" -ForegroundColor Gray
            continue
        }
    }
    
    if (-not $foundPackage) {
        Write-Host "No package found with '1cv8.cf' file" -ForegroundColor Red
        return $null
    }
    
    $downloadUri = $foundPackage.DownloadUri
	    
    Write-Host "Downloading file: $($cfFile.file_name)" -ForegroundColor Yellow
    $fileResponse = Invoke-WebRequest -Uri $downloadUri -Method Get -Headers $headers -UseBasicParsing

    # Сохраняем файл
	$packageVersion = $foundPackage.Version
	$fileName = $packageVersion + ".cf"
	$localFilePath = Join-Path -Path $releasePath -ChildPath $fileName
    $fileResponse.RawContentStream.Position = 0
    $fileStream = [System.IO.File]::Create($localFilePath)
    $fileResponse.RawContentStream.CopyTo($fileStream)
    $fileStream.Close()

    Write-Host "File downloaded and saved to: $localFilePath" -ForegroundColor Green
    return $localFilePath
}