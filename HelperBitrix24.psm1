#
# Обмен релизами (.cf) через Диск Bitrix24 (self-hosted) по входящему веб-хуку.
#
# Совместимость: Windows PowerShell 5.1 (планировщик на сервере) и PowerShell 7+.
#
# Релиз ~800+ МБ одним запросом REST не загрузить (base64 в памяти, post_max_size, таймауты),
# поэтому файл режется на части (по умолчанию 32 МБ), каждая часть - отдельный файл на Диске:
#   <версия>.cf.part001, <версия>.cf.part002, ...
# Последним загружается манифест <версия>.cf.manifest.json (размер, SHA256, список частей).
# Релиз считается опубликованным только при наличии манифеста.
#
# credentials.json:
#   {"server": "https://intranet.oooslk.ru", "serverType": "bitrix24 REST-API",
#     "logintypes": [{"loginType": "webhook", "user": "<ID пользователя>", "password": "<КЛЮЧ веб-хука>"}],
#     "databases": [{"name": "acc3-slk", "internal": "<ID папки на Диске>", "partSizeMB": 32}]}
#   databases.name - имя пакета (pacName), internal - ID папки Диска, partSizeMB - необязательно.
#

function Get-Bitrix24Context {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$b24Server,
        [string]$folderName
    )

    $serverConfig = Get-ServerConfig -mainConfig $mainConfig -server $b24Server
    $login = Get-LoginFromConfig -serverConfig $serverConfig -loginType "webhook"
    $folderConfig = Get-DataBaseConfig -serverConfig $serverConfig -baseName $folderName

    $partSizeMB = 32
    if ($folderConfig.partSizeMB) { $partSizeMB = [int]$folderConfig.partSizeMB }

    return [pscustomobject]@{
        WebhookUrl    = "$($b24Server.TrimEnd('/'))/rest/$($login.user)/$($login.password)/"
        FolderId      = [int]$folderConfig.internal
        PartSizeBytes = [int]($partSizeMB * 1MB)
    }
}

function Invoke-Bitrix24Rest {
    param (
        [pscustomobject]$context,
        [string]$method,
        [hashtable]$body = @{},
        [string]$bodyJson,
        [int]$timeoutSec = 120,
        [int]$retryCount = 3
    )

    # Windows PowerShell 5.1 по умолчанию может не включать TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # Ключ веб-хука в URL - в логи/ошибки его не выводим
    $uri = "$($context.WebhookUrl)$method.json"
    if (-not $bodyJson) { $bodyJson = $body | ConvertTo-Json -Depth 5 -Compress }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    for ($attempt = 1; $true; $attempt++) {
        $statusCode = 0
        $detail = ""
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Body $bytes `
                -ContentType 'application/json; charset=utf-8' -TimeoutSec $timeoutSec
            if ($response.error) {
                throw "Bitrix24 $method : $($response.error) $($response.error_description)"
            }
            return $response
        }
        catch {
            $detail = $_.Exception.Message
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }

            # Логические ошибки (нет прав, нет папки и т.п.) повторять бессмысленно
            $transient = ($statusCode -eq 0) -or ($statusCode -ge 500) -or ($statusCode -eq 429) `
                -or ($detail -match 'QUERY_LIMIT_EXCEEDED')
            if (-not $transient -or $attempt -ge $retryCount) {
                throw "Bitrix24 $method failed (HTTP $statusCode): $detail"
            }
            Write-Host "[WARN] Bitrix24 $method attempt $attempt failed: $detail" -ForegroundColor Yellow
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Get-Bitrix24FolderFiles {
    param ([pscustomobject]$context)

    $files = @()
    $start = 0
    do {
        $response = Invoke-Bitrix24Rest -context $context -method 'disk.folder.getchildren' `
            -body @{ id = $context.FolderId; start = $start }
        $files += @($response.result | Where-Object { $_.TYPE -eq 'file' })
        $start = $response.next
    } while ($null -ne $response.next)

    return $files
}

function Remove-Bitrix24File {
    param (
        [pscustomobject]$context,
        [int]$fileId
    )
    Invoke-Bitrix24Rest -context $context -method 'disk.file.delete' -body @{ id = $fileId } | Out-Null
}

function Send-Bitrix24File {
    param (
        [pscustomobject]$context,
        [string]$name,
        [byte[]]$bytes,
        [int]$count
    )

    # JSON собираем вручную: ConvertTo-Json на десятках МБ base64 очень медленный в PS 5.1
    $base64 = [Convert]::ToBase64String($bytes, 0, $count)
    $nameJson = $name | ConvertTo-Json -Compress
    $json = '{"id":' + $context.FolderId + ',"data":{"NAME":' + $nameJson + '},"fileContent":[' + $nameJson + ',"' + $base64 + '"]}'
    Invoke-Bitrix24Rest -context $context -method 'disk.folder.uploadfile' -bodyJson $json `
        -timeoutSec 900 -retryCount 1 | Out-Null
}

function Send-Bitrix24FileWithRetry {
    param (
        [pscustomobject]$context,
        [string]$name,
        [byte[]]$bytes,
        [int]$count,
        [int]$attempts = 3
    )

    for ($attempt = 1; $true; $attempt++) {
        try {
            Send-Bitrix24File -context $context -name $name -bytes $bytes -count $count
            return
        }
        catch {
            $errorMessage = $_.Exception.Message
            if ($attempt -ge $attempts) { throw }
            Write-Host "[WARN] Upload '$name' attempt $attempt failed: $errorMessage" -ForegroundColor Yellow
            Start-Sleep -Seconds (10 * $attempt)

            # Файл мог создаться, хотя ответ не получен: целый оставляем, битый удаляем
            $created = @(Get-Bitrix24FolderFiles -context $context) | Where-Object { $_.NAME -eq $name } | Select-Object -First 1
            if ($created) {
                if ([int64]$created.SIZE -eq $count) { return }
                Remove-Bitrix24File -context $context -fileId ([int]$created.ID)
            }
        }
    }
}

function Get-Bitrix24SortedManifests {
    <#
    .SYNOPSIS
    Манифесты релизов от новых к старым по имени: <версия>-<гггг-мм-дд-ччмм>.cf.manifest.json.
    Версия сравнивается как число по компонентам (3.0.99 < 3.0.100), затем дата-время из имени.
    Имена другого вида считаются самыми старыми и между собой упорядочиваются по времени загрузки.
    #>
    param ([object[]]$manifestFiles)

    $versionKey = {
        if ($_.NAME -match '^(\d+(?:\.\d+){1,3})-(.+)\.cf\.manifest\.json$') { [version]$Matches[1] } else { [version]'0.0' }
    }
    $stampKey = {
        if ($_.NAME -match '^(\d+(?:\.\d+){1,3})-(.+)\.cf\.manifest\.json$') { $Matches[2] } else { '' }
    }
    $createdKey = { [DateTimeOffset]$_.CREATE_TIME }

    return @($manifestFiles | Sort-Object -Property @{ Expression = $versionKey }, @{ Expression = $stampKey }, @{ Expression = $createdKey } -Descending)
}

function Publish-ReleaseToBitrix24Disk {
    <#
    .SYNOPSIS
    Загружает .cf релиз в папку Диска Bitrix24 частями + манифест.
    .PARAMETER KeepVersions
    После успешной загрузки удалить старые релизы, оставив столько последних (по порядку
    Get-Bitrix24SortedManifests). По умолчанию 2 - предыдущий и текущий. 0 - ничего не удалять.
    Только что загруженный релиз не удаляется никогда.
    #>
    param (
        [pscustomobject[]]$mainConfig,
        [string]$b24Server,
        [string]$folderName,
        [string]$FilePath,
        [string]$PackageVersion,
        [int]$KeepVersions = 2
    )

    $context = Get-Bitrix24Context -mainConfig $mainConfig -b24Server $b24Server -folderName $folderName
    $file = Get-Item -LiteralPath $FilePath
    $partCount = [int][math]::Ceiling($file.Length / $context.PartSizeBytes)

    $existing = @{}
    foreach ($f in @(Get-Bitrix24FolderFiles -context $context)) { $existing[$f.NAME] = $f }

    # Релиз с тем же именем перезаливается: пока идет загрузка, он не должен быть виден
    $manifestName = "$PackageVersion.cf.manifest.json"
    if ($existing.ContainsKey($manifestName)) {
        Remove-Bitrix24File -context $context -fileId ([int]$existing[$manifestName].ID)
    }

    Write-Host "Uploading '$($file.Name)' ($([math]::Round($file.Length / 1MB, 1)) MB) to $b24Server, folder $($context.FolderId): $partCount part(s)" -ForegroundColor Yellow

    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $stream = [System.IO.File]::OpenRead($file.FullName)
    $buffer = New-Object byte[] $context.PartSizeBytes
    $parts = @()
    try {
        for ($i = 1; $i -le $partCount; $i++) {
            $read = 0
            while ($read -lt $buffer.Length) {
                $n = $stream.Read($buffer, $read, $buffer.Length - $read)
                if ($n -le 0) { break }
                $read += $n
            }
            $hash.AppendData($buffer, 0, $read)

            $partName = '{0}.cf.part{1:D3}' -f $PackageVersion, $i
            $parts += [ordered]@{ name = $partName; size = $read }

            $old = $existing[$partName]
            if ($old -and ([int64]$old.SIZE -eq $read)) {
                Write-Host "Part $i/$partCount exists, skipped: $partName" -ForegroundColor Gray
                continue
            }
            if ($old) { Remove-Bitrix24File -context $context -fileId ([int]$old.ID) }

            Send-Bitrix24FileWithRetry -context $context -name $partName -bytes $buffer -count $read
            Write-Host "Part $i/$partCount uploaded: $partName ($read bytes)" -ForegroundColor Gray
        }
    }
    finally {
        $stream.Dispose()
    }

    $sha256 = [BitConverter]::ToString($hash.GetHashAndReset()).Replace('-', '').ToLowerInvariant()
    $manifest = [ordered]@{
        format  = 1
        version = $PackageVersion
        size    = $file.Length
        sha256  = $sha256
        parts   = $parts
    }
    $manifestBytes = [System.Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 5))
    Send-Bitrix24FileWithRetry -context $context -name $manifestName -bytes $manifestBytes -count $manifestBytes.Length
    Write-Host "Release published: $PackageVersion (sha256 $sha256)" -ForegroundColor Green

    if ($KeepVersions -gt 0) {
        Remove-OldBitrix24Releases -context $context -keepVersions $KeepVersions -protectVersion $PackageVersion
    }
}

function Remove-OldBitrix24Releases {
    param (
        [pscustomobject]$context,
        [int]$keepVersions,
        [string]$protectVersion
    )

    $files = @(Get-Bitrix24FolderFiles -context $context)
    $manifests = Get-Bitrix24SortedManifests -manifestFiles @($files | Where-Object { $_.NAME -like '*.cf.manifest.json' })

    foreach ($manifestFile in ($manifests | Select-Object -Skip $keepVersions)) {
        $version = $manifestFile.NAME -replace '\.cf\.manifest\.json$', ''
        if ($version -eq $protectVersion) { continue }
        # Сначала манифест - релиз перестает быть доступным, потом части
        Remove-Bitrix24File -context $context -fileId ([int]$manifestFile.ID)
        $prefix = "$version.cf.part"
        foreach ($part in ($files | Where-Object { $_.NAME.StartsWith($prefix) })) {
            Remove-Bitrix24File -context $context -fileId ([int]$part.ID)
        }
        Write-Host "Old release removed from Bitrix24: $version" -ForegroundColor Gray
    }
}

function Save-Bitrix24File {
    param (
        [pscustomobject]$context,
        [int]$fileId,
        [string]$outFile,
        [int64]$expectedSize
    )

    $info = Invoke-Bitrix24Rest -context $context -method 'disk.file.get' -body @{ id = $fileId }
    $downloadUrl = $info.result.DOWNLOAD_URL
    if (-not $downloadUrl) { throw "Bitrix24: no DOWNLOAD_URL for file id $fileId" }

    $ProgressPreference = 'SilentlyContinue'   # в PS 5.1 прогресс-бар замедляет загрузку в разы
    $response = Invoke-WebRequest -Uri $downloadUrl -Method Get -OutFile $outFile -PassThru `
        -UseBasicParsing -TimeoutSec 900

    if ("$($response.Headers['Content-Type'])" -match 'text/html') {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
        throw "Bitrix24: DOWNLOAD_URL for file id $fileId returned HTML (authorization required?)"
    }
    if ($expectedSize -gt 0 -and (Get-Item -LiteralPath $outFile).Length -ne $expectedSize) {
        throw "Bitrix24: file id $fileId size mismatch: expected $expectedSize, got $((Get-Item -LiteralPath $outFile).Length)"
    }
}

function Get-LatestReleaseFromBitrix24Disk {
    <#
    .SYNOPSIS
    Скачивает последний опубликованный релиз из папки Диска Bitrix24, собирает .cf из частей
    и проверяет SHA256. Возвращает путь вида <releasePath>\<folderName>\<версия>.cf
    #>
    param (
        [pscustomobject[]]$mainConfig,
        [string]$b24Server,
        [string]$folderName,
        [string]$releasePath
    )

    $context = Get-Bitrix24Context -mainConfig $mainConfig -b24Server $b24Server -folderName $folderName

    $files = @(Get-Bitrix24FolderFiles -context $context)
    $byName = @{}
    foreach ($f in $files) { $byName[$f.NAME] = $f }

    $packagePath = Join-Path -Path $releasePath -ChildPath $folderName
    if (-not (Test-Path $packagePath)) { New-Item $packagePath -ItemType Directory | Out-Null }

    $manifests = Get-Bitrix24SortedManifests -manifestFiles @($files | Where-Object { $_.NAME -like '*.cf.manifest.json' })
    if ($manifests.Count -eq 0) { throw "No releases (*.cf.manifest.json) in Bitrix24 folder $($context.FolderId)" }

    # Берем самый новый релиз, у которого на Диске есть все части
    $manifest = $null
    foreach ($manifestFile in $manifests) {
        $tmp = Join-Path $packagePath "$($manifestFile.NAME).tmp"
        try {
            Save-Bitrix24File -context $context -fileId ([int]$manifestFile.ID) -outFile $tmp -expectedSize 0
            $candidate = Get-Content -LiteralPath $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        $complete = $true
        foreach ($part in $candidate.parts) {
            $partFile = $byName[$part.name]
            if (-not $partFile -or [int64]$partFile.SIZE -ne [int64]$part.size) { $complete = $false; break }
        }
        if ($complete) { $manifest = $candidate; break }
        Write-Host "Release $($candidate.version) is incomplete in Bitrix24, trying previous" -ForegroundColor Yellow
    }
    if (-not $manifest) { throw "No complete releases in Bitrix24 folder $($context.FolderId)" }

    $localFilePath = Join-Path -Path $packagePath -ChildPath "$($manifest.version).cf"
    if ((Test-Path $localFilePath) -and ((Get-Item -LiteralPath $localFilePath).Length -eq [int64]$manifest.size)) {
        Write-Host "Release exists: $localFilePath" -ForegroundColor Yellow
        return $localFilePath
    }

    Write-Host "Downloading $($manifest.version): $(@($manifest.parts).Count) part(s), $([math]::Round([int64]$manifest.size / 1MB, 1)) MB" -ForegroundColor Yellow

    $partialPath = "$localFilePath.partial"
    $partTmp = "$localFilePath.part.tmp"
    $hash = [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $buffer = New-Object byte[] (4MB)
    $output = [System.IO.File]::Create($partialPath)
    try {
        $number = 0
        foreach ($part in $manifest.parts) {
            $number++
            Save-Bitrix24File -context $context -fileId ([int]$byName[$part.name].ID) -outFile $partTmp -expectedSize ([int64]$part.size)
            $partStream = [System.IO.File]::OpenRead($partTmp)
            try {
                while (($n = $partStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $output.Write($buffer, 0, $n)
                    $hash.AppendData($buffer, 0, $n)
                }
            }
            finally {
                $partStream.Dispose()
            }
            Remove-Item -LiteralPath $partTmp -Force
            Write-Host "Part $number/$(@($manifest.parts).Count) downloaded" -ForegroundColor Gray
        }
        $output.Dispose()

        $sha256 = [BitConverter]::ToString($hash.GetHashAndReset()).Replace('-', '').ToLowerInvariant()
        if ($sha256 -ne $manifest.sha256) {
            throw "Bitrix24: SHA256 mismatch for $($manifest.version): expected $($manifest.sha256), got $sha256"
        }
        Move-Item -LiteralPath $partialPath -Destination $localFilePath -Force
    }
    catch {
        $output.Dispose()
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        Remove-Item -LiteralPath $partTmp -Force -ErrorAction SilentlyContinue
    }

    Write-Host "File downloaded and saved to: $localFilePath" -ForegroundColor Green
    return $localFilePath
}
