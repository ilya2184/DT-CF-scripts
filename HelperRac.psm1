if (-not (Get-Command "rac" -ErrorAction SilentlyContinue)) {
    $errorMessage = "'rac' not found in PATH. Install 1C:Enterprice server components and add it to PATH."
    Write-Error -Message $errorMessage -Category ResourceUnavailable
    throw $errorMessage  # Прерываем загрузку модуля
}

function Get-RacInfobaseMap {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$adminServer,
        [string]$ibServer
    )

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $clLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "clusteradmin"
    $clAdmin = $clLogin.user
    $clPassword = $clLogin.password
    $clId = $ibServerConfig.id

    $arguments = @("infobase", "summary", "list",
        $adminServer,
        "--cluster=$clId", "--cluster-user=$clAdmin", "--cluster-pwd=$clPassword"
    )

    $tempOutputFile = [System.IO.Path]::GetTempFileName()
    Start-Process -FilePath "rac" -ArgumentList $arguments -NoNewWindow -Wait -RedirectStandardOutput $tempOutputFile

    $output = Get-Content $tempOutputFile

    if (-not $output) {
        Remove-Item $tempOutputFile
        throw "rac returned empty content for infobase summary list"
    }

    [hashtable]$infobaseMap = @{}

    $patternInfobase = 'infobase\s+:\s+([0-9a-fA-F-]+)'
    $patternName = 'name\s+:\s+(.*)'

    $currentInfobaseId = $null
    foreach ($line in $output) {
        if ($line -match $patternInfobase) {
            $currentInfobaseId = $matches[1]
        }
        elseif ($line -match $patternName) {
            $infobaseName = $matches[1] -replace '[^\w-]', '' # только буквы, цифры, тире и подчеркивание
            if ($currentInfobaseId -and $infobaseName) {
                $infobaseMap[$infobaseName] = $currentInfobaseId
            }
            $currentInfobaseId = $null
        }
    }

    Remove-Item $tempOutputFile

    return $infobaseMap
}

function Set-RacInfobaseSessionBlock {
    param (
        [pscustomobject[]]$mainConfig,
        [hashtable]$infobaseMap,
        [string]$adminServer,
        [string]$ibServer,
        [string]$ibName,
        [bool]$blockSessions
    )

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $clLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "clusteradmin"
    $clUser = $clLogin.user
    $clPassword = $clLogin.password
    $clId = $ibServerConfig.id

    $ibId = $infobaseMap[$ibName]

    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $sessionsDeny = if ($blockSessions) { "on" } else { "off" }

    # Формируем команду для блокировки или разблокировки сеансов
    $arguments = @("infobase", "update",
        $adminServer,
        "--cluster=$clId", "--cluster-user=$clUser", "--cluster-pwd=$clPassword",
        "--infobase=$ibId", "--infobase-user=$ibUser", "--infobase-pwd=$ibPassword",
        "--sessions-deny=$sessionsDeny", "--scheduled-jobs-deny=$sessionsDeny", "--permission-code=0000"
    )
    
    # Выполняем команду с использованием Start-Process
    Start-Process -FilePath "rac" -ArgumentList $arguments -NoNewWindow -Wait

    Write-Host "Sessions lock $sessionsDeny for $ibServer\$ibName." -ForegroundColor Yellow
}

function Stop-RacInfobaseSessions {
    param (
        [pscustomobject[]]$mainConfig,
        [hashtable]$infobaseMap,
        [string]$adminServer,
        [string]$ibServer,
        [string]$ibName
    )

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $clLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "clusteradmin"
    $clUser = $clLogin.user
    $clPassword = $clLogin.password
    $clId = $ibServerConfig.id

    $ibId = $infobaseMap[$ibName]

    $getSessionArgs = @("session", "list",
        $adminServer,
        "--cluster=$clId", "--cluster-user=$clUser", "--cluster-pwd=$clPassword",
        "--infobase=$ibId"
    )

    $tempOutputFile = [System.IO.Path]::GetTempFileName()
    
    Start-Process -FilePath "rac" -ArgumentList $getSessionArgs -NoNewWindow -Wait -RedirectStandardOutput $tempOutputFile

    $output = Get-Content $tempOutputFile

    if (-not $output) {
        Write-Host "  rac returned empty content for session list" -ForegroundColor Blue
        return
    }

    $sessionIds = @()

    $patternSession = 'session\s+:\s+([0-9a-fA-F-]+)'

    foreach ($line in $output) {
        if ($line -match $patternSession) {
            $sessionIds += $matches[1]
        }
    }

    Remove-Item $tempOutputFile

    foreach ($sessionId in $sessionIds) {
        $stopSessionArgs = @("session", "terminate",
            $adminServer,
            "--cluster=$clId", "--cluster-user=$clUser", "--cluster-pwd=$clPassword",
            "--session=$SessionId")
        Start-Process -FilePath "rac" -ArgumentList $stopSessionArgs -NoNewWindow -Wait
    }

    return $sessionIds
}
