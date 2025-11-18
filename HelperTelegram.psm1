function Send-TelegramMessageToUsers {
    <#
    .SYNOPSIS
        Отправляет сообщение пользователям через Telegram Bot API с поддержкой форматирования.

    .DESCRIPTION
        Функция отправляет сообщение в группу пользователей через Telegram Bot API.
        Поддерживает форматирование MarkdownV2: выделение жирным текстом и выделение кода.

        Форматирование MarkdownV2:
        - Жирный текст: *текст* или **текст**
        - Inline код: `код`
        - Блок кода: ```код```
        - Курсив: _текст_
        - Ссылка: [Текст](URL)

        ВАЖНО: В MarkdownV2 следующие символы должны быть экранированы обратным слешем (\):
        _ * [ ] ( ) ~ ` > # + - = | { } . !
        Если символ используется для форматирования (например, * для жирного, [ ] ( ) для ссылок), экранировать НЕ нужно.
        Однако специальные символы внутри текста ссылки и URL должны быть экранированы, если они не являются частью разметки.

    .PARAMETER mainConfig
        Массив объектов конфигурации основного сервера.

    .PARAMETER message
        Текст сообщения для отправки. Поддерживает форматирование MarkdownV2.

    .EXAMPLE
        # Простое сообщение без форматирования
        Send-TelegramMessageToUsers -mainConfig $config -message "Система работает нормально"

    .EXAMPLE
        # Сообщение с жирным текстом
        Send-TelegramMessageToUsers -mainConfig $config -message "*Внимание\!* Требуется действие"

    .EXAMPLE
        # Сообщение с кодом и жирным текстом
        # В PowerShell для получения одного backtick в строке используйте двойной backtick
        $msg = "*Статус базы данных:* ``test_db``"
        Send-TelegramMessageToUsers -mainConfig $config -message $msg

    .EXAMPLE
        # Сообщение с блоком кода
        $msg = @"
        *Команда выполнена успешно:*
        ```
        Get-Process | Where-Object {`$_.CPU -gt 100}
        ```
        Результат сохранен.
        "@
        Send-TelegramMessageToUsers -mainConfig $config -message $msg

    .EXAMPLE
        # Комбинированное форматирование
        $msg = "*Скрипт завершен*`nСтатус: ``SUCCESS`` `nВремя выполнения: _2 минуты_"
        Send-TelegramMessageToUsers -mainConfig $config -message $msg

    .EXAMPLE
        # Сообщение со ссылкой
        # Синтаксис ссылки в MarkdownV2: [Текст](URL)
        $msg = "*Результат готов:*`nПросмотреть можно по [ссылке](https://my.link.local/point)"
        Send-TelegramMessageToUsers -mainConfig $config -message $msg

    .EXAMPLE
        # Сообщение со ссылкой и жирным текстом в тексте ссылки
        $msg = "Перейдите на [*страницу*](https://my.link.local/point) для просмотра результатов"
        Send-TelegramMessageToUsers -mainConfig $config -message $msg

    .NOTES
        Для работы функции необходимо наличие настроек Telegram Bot в конфигурации.
        Группа пользователей должна быть указана в параметре "UsersGroup" конфигурации базы данных.
    #>
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
        parse_mode = "MarkdownV2"
    }

    Invoke-RestMethod -Uri $url -Method Post -Body $body

}
