if (-not (Get-Command "ibcmd" -ErrorAction SilentlyContinue)) {
    $errorMessage = "'ibcmd' not found in PATH. Install 1C:Enterprice server components and add it to PATH."
    Write-Error -Message $errorMessage -Category ResourceUnavailable
    throw $errorMessage  # Прерываем загрузку модуля
}

function Get-UniqueExportName {
    $length = 8
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $random = -join ((Get-Random -Count $length -InputObject $chars.ToCharArray()) | Sort-Object { Get-Random })
    return $random
}

function Export-DBConfigToXML {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName
    )

    Write-Host "Export $ibServer\$ibName" -ForegroundColor Yellow

    $exportName = Get-UniqueExportName
    $srvDataPath = Join-Path -Path $Env:TEMP -ChildPath ("srv" + $exportName)
    $xmlPath = Join-Path -Path $Env:TEMP -ChildPath $exportName

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    if ($ibServerConfig.serverType -eq "file") {
        $dbPath = $ibConfig.path
        $exportArgs = @("infobase", "config", "export",
            "--ignore-unresolved-refs"
            "--data=`"$srvDataPath`"",
            "--database-path=`"$dbPath`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$xmlPath`"")
    }
    else {
        $dbServer = $ibConfig.dbserver
        $dbName = $ibConfig.dbname
        $dbServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $dbServer
        $dbms = $dbServerConfig.serverType
        $dbLogin = Get-LoginFromConfig -serverConfig $dbServerConfig -loginType "databaseuser"
        $dbUser = $dbLogin.user
        $dbPassword = $dbLogin.password
        $exportArgs = @("infobase", "config", "export",
            "--ignore-unresolved-refs"
            "--data=`"$srvDataPath`"",
            "--dbms=`"$dbms`"", "--database-server=`"$dbServer`"", "--database-name=`"$dbName`"",
            "--database-user=`"$dbUser`"", "--database-password=`"$dbPassword`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$xmlPath`"")
    }

    Start-Process "ibcmd" -ArgumentList $exportArgs -NoNewWindow -Wait
    Remove-Item -Path "$srvDataPath" -Recurse -Force
    Write-Host "Now we have 1c-xml in $xmlPath" -ForegroundColor Yellow
    return $xmlPath
}

function Export-XMLToCF {
    param (
        [string]$xmlPath
    )

    Write-Host "Creating database from 1C-XML $xmlPath" -ForegroundColor Yellow

    $srvName = Get-UniqueExportName
    $srvDataPath = Join-Path -Path $Env:TEMP -ChildPath ("srv" + $srvName)

    $dbName = Get-UniqueExportName
    $dbPath = Join-Path -Path $Env:TEMP -ChildPath ("db" + $dbName)

    $importArgs = @("infobase", "create",
        "--data=`"$srvDataPath`"",
        "--database-path=`"$dbPath`"",
        "--import=`"$xmlPath`"", "--apply", "--force")
    Start-Process "ibcmd" -ArgumentList $importArgs -NoNewWindow -Wait

    $cfName = Get-UniqueExportName
    $cfPath = Join-Path -Path $Env:TEMP -ChildPath ($cfName + ".cf")

    $exportArgs = @("config", "save",
        "--data=`"$srvDataPath`"",
        "--database-path=`"$dbPath`"",
        "--db", "`"$cfPath`"")
    Start-Process "ibcmd" -ArgumentList $exportArgs -NoNewWindow -Wait
    Remove-Item -Path "$dbPath" -Recurse -Force
    Remove-Item -Path "$srvDataPath" -Recurse -Force
    Write-Host "Configuration created $cfPath" -ForegroundColor Yellow

    return $cfPath

}

function Import-ConfigToDBFromCF {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName,
        [string]$releasePath
    )

    Write-Host "Import config from $releasePath to $ibServer\$ibName" -ForegroundColor Yellow

    $srvName = Get-UniqueExportName
    $srvDataPath = Join-Path -Path $Env:TEMP -ChildPath ("srv" + $srvName)

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    if ($ibServerConfig.serverType -eq "file") {
        $dbPath = $ibConfig.path
        $importArgs = @("infobase", "config", "load",
            "--data=`"$srvDataPath`"",
            "--database-path=`"$dbPath`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$releasePath`"")
    }
    else {
        $dbServer = $ibConfig.dbserver
        $dbName = $ibConfig.dbname
        $dbServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $dbServer
        $dbms = $dbServerConfig.serverType
        $dbLogin = Get-LoginFromConfig -serverConfig $dbServerConfig -loginType "databaseuser"
        $dbUser = $dbLogin.user
        $dbPassword = $dbLogin.password
        $importArgs = @("infobase", "config", "load",
            "--data=`"$srvDataPath`"",
            "--dbms=`"$dbms`"", "--database-server=`"$dbServer`"", "--database-name=`"$dbName`"",
            "--database-user=`"$dbUser`"", "--database-password=`"$dbPassword`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$releasePath`"")
    }

    Start-Process "ibcmd" -ArgumentList $importArgs -NoNewWindow -Wait
    Remove-Item -Path "$srvDataPath" -Recurse -Force
    Write-Host "Config $releasePath loaded to $ibServer\$ibName" -ForegroundColor Yellow
}

function Set-SavedConfigToDB {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName
    )

    Write-Host "Appling saved config in $ibServer\$ibName to infobase config" -ForegroundColor Yellow

    $srvName = Get-UniqueExportName
    $srvDataPath = Join-Path -Path $Env:TEMP -ChildPath ("srv" + $srvName)

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    $dbms = $ibServerConfig.serverType
    if ($dbms -eq "file") {
        $dbPath = $ibConfig.path
        $importArgs = @("infobase", "config", "apply", "--force",
            "--data=`"$srvDataPath`"",
            "--database-path=`"$dbPath`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"")
    }
    else {
        $dbServer = $ibConfig.dbserver
        $dbName = $ibConfig.dbname
        $dbServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $dbServer
        $dbms = $dbServerConfig.serverType
        $dbLogin = Get-LoginFromConfig -serverConfig $dbServerConfig -loginType "databaseuser"
        $dbUser = $dbLogin.user
        $dbPassword = $dbLogin.password
        $importArgs = @("infobase", "config", "apply", "--force",
            "--data=`"$srvDataPath`"",
            "--dbms=`"$dbms`"", "--database-server=`"$dbServer`"", "--database-name=`"$dbName`"",
            "--database-user=`"$dbUser`"", "--database-password=`"$dbPassword`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"")
    }

    Start-Process "ibcmd" -ArgumentList $importArgs -NoNewWindow -Wait
    Remove-Item -Path "$srvDataPath" -Recurse -Force
    Write-Host "Saved config applied for $ibServer\$ibName" -ForegroundColor Yellow
}

function Backup-DataBase {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$ibServer,
        [string]$ibName,
        [string]$dtsPath,
        [bool]$addDateToName
    )

    Write-Host "Database $ibServer\$ibName dump to $dtsPath" -ForegroundColor Yellow

    $srvName = Get-UniqueExportName
    $srvDataPath = Join-Path -Path $Env:TEMP -ChildPath ("srv" + $srvName)

    $ibServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $ibServer
    $ibLogin = Get-LoginFromConfig -serverConfig $ibServerConfig -loginType "ibadmin"
    $ibUser = $ibLogin.user
    $ibPassword = $ibLogin.password

    $ibConfig = Get-DataBaseConfig -serverConfig $ibServerConfig -baseName $ibName

    $dbServer = if ($ibServerConfig.serverType -eq "file") { $ibServer } else { $ibConfig.dbserver }
    $dbName = if ($ibServerConfig.serverType -eq "file") { $ibName } else { $ibConfig.dbname } 
    $dbServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $dbServer
    $dbConfig = Get-DataBaseConfig -serverConfig $dbServerConfig -baseName $dbName
    $dumpPath = Join-Path -Path $dtsPath -ChildPath ($dbConfig.internal)
    if (-not (Test-Path $dumpPath)) {New-Item -Path $dumpPath -ItemType Directory -Force}

    $dateString = if ($addDateToName -eq $true) { "-" + (Get-Date).ToString('yyyy-MM-dd-HH-mm') } else { $dateString = "" }
    $dumpFileName = $dbName + $dateString + ".dt"
    $dumpFilePath = Join-Path -Path $dumpPath -ChildPath $dumpFileName

    if ($ibServerConfig.serverType -eq "file") {
        $dbPath = $ibConfig.path
        $importArgs = @("infobase", "dump",
            "--data=`"$srvDataPath`"",
            "--database-path=`"$dbPath`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$dumpFilePath`"")
    }
    else {
        $dbServer = $ibConfig.dbserver
        $dbName = $ibConfig.dbname
        $dbServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $dbServer
        $dbms = $dbServerConfig.serverType
        $dbLogin = Get-LoginFromConfig -serverConfig $dbServerConfig -loginType "databaseuser"
        $dbUser = $dbLogin.user
        $dbPassword = $dbLogin.password
        $importArgs = @("infobase", "dump",
            "--data=`"$srvDataPath`"",
            "--dbms=`"$dbms`"", "--database-server=`"$dbServer`"", "--database-name=`"$dbName`"",
            "--database-user=`"$dbUser`"", "--database-password=`"$dbPassword`"",
            "--user=`"$ibUser`"", "--password=`"$ibPassword`"",
            "`"$dumpFilePath`"")
    }

    Start-Process "ibcmd" -ArgumentList $importArgs -NoNewWindow -Wait
    Remove-Item -Path "$srvDataPath" -Recurse -Force
    Write-Host "Database $ibServer\$ibName dumped to $dumpFilePath" -ForegroundColor Yellow
}