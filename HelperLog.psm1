Function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$logMessage,
        [string]$logFile,
        [bool]$isError
    )

    # Формируем временную метку
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Определяем префикс в зависимости от типа сообщения
    $prefix = if ($isError) { "[ERROR]" } else { "[INFO]" }
    
    # Формируем итоговое сообщение
    $logMessageFull = "$timestamp $prefix $logMessage"
    
    # Выводим в консоль с указанным цветом
    Write-Host $logMessageFull -ForegroundColor White
    
    # Если указан файл — записываем в файл
    if ($logFile) {
        try {
            Add-Content -Path $logFile -Value $logMessageFull -Encoding UTF8
        }
        catch {
            Write-Warning "Не удалось записать в файл $logFile : $_"
        }
    }
}