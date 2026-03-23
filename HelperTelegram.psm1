function Send-TelegramMessageToUsers {
    param (
        [pscustomobject[]]$mainConfig,
        [string]$message
    )
    
    $tgServer = "https://api.telegram.org"
    $tgServerConfig = Get-ServerConfig -mainConfig $mainConfig -server $tgServer
    $tgLogin = Get-LoginFromConfig -serverConfig $tgServerConfig -loginType "GL2Tg Issues Bot"
    $tgToken = $tgLogin.password
    
    $grupConfig = Get-DataBaseConfig -serverConfig $tgServerConfig -baseName "UsersGroup"
    $chatId = $grupConfig.internal
    $url = "https://api.telegram.org/bot$tgToken/sendmessage"
    $body = @{
        chat_id = $chatId
        text = $message
    }

    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $body -TimeoutSec 10 -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        $errMsg = "Telegram send failed: $($_.Exception.Message)"
        Write-Host "[WARN] $errMsg" -ForegroundColor Yellow
        Write-Host "[WARN] Сообщение не отправлено (таймаут 10 секунд или сервер недоступен)." -ForegroundColor Yellow
        return $false
    }
}
