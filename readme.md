# Вспомогательные PowerShell-обёртки для работы с инфраструктурой 1С

## Описание

В этом репозитории собраны вспомогательные PowerShell-модули (`*.psm1`) для автоматизации типовых задач администрирования и обслуживания инфраструктуры 1С: управление кластерами, базами данных, резервным копированием, обновлением конфигураций и интеграцией с внешними сервисами (YARD, Telegram и др.).

## Структура проекта

- **Модули-обёртки (`*.psm1`)**  
  Реализуют функции для работы с инструментами 1С (`ibcmd`, `rac`, `1cedtcli`), а также вспомогательные функции для работы с файлами, Telegram, YARD и др.
- **Конфигурационный файл**  
  - `credentials.json` (пример: `example.credentials.json`) — содержит параметры подключения к серверам, базам данных и сервисам, а также учетные данные.

## Быстрый старт

**Скопируйте и настройте файл `credentials.json`**  
   Используйте `example.credentials.json` как шаблон, заполните своими данными.

## Основные модули

- `HelperCredentials.psm1` — работа с конфигом и учетными данными
- `HelperIbcmd.psm1` — экспорт/импорт/обновление конфигураций через ibcmd
- `HelperRac.psm1` — управление кластерами и сессиями через rac
- `Helper1cedtcli.psm1` — работа с проектами EDT
- `HelperFiles.psm1` — управление резервными копиями
- `HelperTelegram.psm1`, `HelperYard.psm1` и др. — интеграция с внешними сервисами

## Требования

- PowerShell 7+
- Установленные утилиты: `ibcmd`, `rac`, `1cedtcli`, `yard` (должны быть в PATH)
- Заполненный `credentials.json`

## Примечания

- Все скрипты и модули ориентированы на автоматизацию типовых задач DevOps/администрирования 1С.

## Пример: обновление ветки поставщика и выгрузка изменений в git

Ниже приведён пример автоматизации обновления типовой базы 1С из YARD, применения обновлений, экспорта конфигурации и выгрузки изменений в git. Все параметры берутся из вашего `credentials.json`.

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Получаем текущую директорию
[string]$currentDir = $PSScriptRoot
if ($currentDir -eq "") {$currentDir = Get-Location}
$modulesDir = $currentDir

# Импортируем необходимые модули
Import-Module (Join-Path -Path $modulesDir -ChildPath "HelperCredentials.psm1")
$ErrorActionPreference = "Stop"
try {
    Import-Module (Join-Path $modulesDir "HelperYard.psm1")
    Import-Module (Join-Path $modulesDir "Helper1cv8.psm1")
    Import-Module (Join-Path $modulesDir "HelperIbcmd.psm1")
    Import-Module (Join-Path $modulesDir "Helper1cedtcli.psm1")
}
catch {
    Write-Error "Module import error: $_"
    exit 1
}

# Загружаем основной конфиг
$mainConfigPath = Join-Path $currentDir "credentials.json"
$mainConfig = Get-MainConfig -mainConfigPath $mainConfigPath

# В credentials.json ожидается:
#  наличие типовой базы: полностью на поддержке, без возможности изменений
#  существует рабочеее пространство ЕДТ с проектом подключенным находящемся на ветке поставщика
$ibServer = "onecfiles"
$ibName = "Accounting30"

# Получаем обновления из YARD и применяем их к базе
$yardTemplatesPath = Join-Path $currentDir "yard-templates"
$yardWorkspace = Get-UpdatesFromSite -mainConfig $mainConfig -yardTemplatesPath $yardTemplatesPath -yardTemplateName "Accounting30"
Update-OnecBasesFromCfu -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName -cfusPath $yardWorkspace

# Экспортируем конфигурацию базы в 1C-XML
$xmlPath = Export-DBConfigToXML -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName

# Импортируем 1C-XML в рабочее пространство EDT во временный проект
#  заменяем этими файлами существующий crc
#  удаляем временный проект и его файлы
$gitPath = Update-WorkSpaceFromXML -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName -xmlPath $xmlPath

# Получаем версию конфигурации
[xml]$configInfo = Get-Content -Path (Join-Path -Path $xmlPath -ChildPath "Configuration.xml")
[string]$configVersion = $configInfo.MetaDataObject.Configuration.Properties.Version

# Удаляем временные файлы
Remove-Item -Path "$xmlPath" -Recurse -Force

# Фиксируем и отправляем изменения в git
Set-Location -Path $gitPath
git add .
git commit -m "Обновление $configVersion"
```

## Пример: уменьшение размеров ролей
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

[string]$currentDir = $PSScriptRoot
if ($currentDir -eq "") {$currentDir = Get-Location}
$modulesDir = $currentDir
Import-Module (Join-Path -Path $modulesDir -ChildPath "HelperFiles.psm1")

$xmlPath = "C:\Temp\Accounting3"
Optimize-RoleSizes -sourcePath $xmlPath
```

## Пример: массовое развертывание релиза бухгалтерии в несколько баз с оповещением пользователей

Этот пример демонстрирует автоматизацию развертывания релиза (файла конфигурации .cf) в несколько информационных баз 1С с помощью вспомогательных модулей, а также отправку уведомлений пользователям через Telegram. Все параметры берутся из вашего `credentials.json`.

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Получаем текущую директорию
[string]$currentDir = $PSScriptRoot
if ($currentDir -eq "") {$currentDir = Get-Location}
$modulesDir = $currentDir

# Импортируем необходимые модули
Import-Module (Join-Path -Path $modulesDir -ChildPath "HelperCredentials.psm1")
$ErrorActionPreference = "Stop"
try {
    Import-Module (Join-Path $modulesDir "HelperReleases.psm1")
    Import-Module (Join-Path $modulesDir "HelperIbcmd.psm1")
    Import-Module (Join-Path $modulesDir "Helper1cv8.psm1")
    Import-Module (Join-Path $modulesDir "HelperRac.psm1")
    Import-Module (Join-Path $modulesDir "HelperTelegram.psm1")
}
catch {
    Write-Error "Module import error: $_"
    exit 1
}

# Загружаем основной конфиг
$mainConfigPath = Join-Path $currentDir "credentials.json"
$mainConfig = Get-MainConfig -mainConfigPath $mainConfigPath

# В credentials.json должны быть описаны все базы и серверы, участвующие в развертывании
$internal = "acc3" # условное название внутренностей базы 1С
$ibServer = "onec-server.domain.local:1541" # сервер, где размещаются базы
$ibNames = @(
    "Acc3-1",
    "Acc3-2")

# Получаем путь к последнему релизу (файлу .cf)
$releasesPath = "D:\YandexDisk\Work\DT-CF"
$releasePath = Get-LatestReleasePath -releasesPath $releasesPath -internal $internal
$backupPath = "D:\YandexDisk\Work\DT-CF"

# Оповещаем пользователей о начале развертывания
$releaseName = [System.IO.Path]::GetFileNameWithoutExtension($releasePath)
$message = "Начато развертывание релиза бухгалтерии. Версия $releaseName. Работа пользователей будет завершена и заблокирована."
Send-TelegramMessageToUsers -mainConfig $mainConfig -message $message

$adminServer = "rac.domain.local:1545"
$infobaseMap = Get-RacInfobaseMap -mainConfig $mainConfig -adminServer $adminServer -ibServer $ibServer
foreach ($ibName in $ibNames) {
    # Размещение релиза в базу (ibcmd)
    Import-ConfigToDBFromCF -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName -releasePath $releasePath

    # Запрещаем создание новых сеансов (rac)
    Set-RacInfobaseSessionBlock -mainConfig $mainConfig -infobaseMap $infobaseMap -adminServer $adminServer `
        -ibServer $ibServer -ibName $ibName -blockSessions $true

    # Завершаем текущие сеансы (rac)
    Stop-RacInfobaseSessions -mainConfig $mainConfig -infobaseMap $infobaseMap -adminServer $adminServer `
        -ibServer $ibServer -ibName $ibName

    Backup-DataBase -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName -dtsPath $backupPath -addDateToName $true

    # Реструктуризация базы (1cv8)
    Update-DBCfg -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName

    # Переходные процедуры обновления (1cv8)
    Update-ibData -mainConfig $mainConfig -ibServer $ibServer -ibName $ibName

    # Разрешаем создание новых сеансов (rac)
    Set-RacInfobaseSessionBlock -mainConfig $mainConfig -infobaseMap $infobaseMap -adminServer $adminServer `
        -ibServer $ibServer -ibName $ibName -blockSessions $false    
}

# Оповещаем пользователей о завершении развертывания
$message = "В рабочих базах бухгалтерии версия $releaseName. Работа пользователей разрешена."
Send-TelegramMessageToUsers -mainConfig $mainConfig -message $message

# Оставляем два последних бэкапа каждой базы
$keepBackupCount = 2
Remove-Backups -backupPath $backupPath -keepBackupCount $keepBackupCount

```
