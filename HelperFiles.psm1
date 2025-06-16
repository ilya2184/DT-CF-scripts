function Remove-Backups {
    param (
        [string]$backupPath,
        [int]$keepBackupCount
    )

    $subDirectories = Get-ChildItem -Path $backupPath -Directory

    foreach ($dir in $subDirectories) {
        $backupFiles = Get-ChildItem -Path $dir.FullName -Filter "*.dt"
    
        $groupedFiles = $backupFiles | Group-Object {
            if ($_.Name -match "^(.*?)-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}\.dt$") {
                return $matches[1]
            }
            return $_.Name
        }
    
        foreach ($group in $groupedFiles) {
            $sortedFiles = $group.Group | Sort-Object {
                if ($_.Name -match "-(\d{4}-\d{2}-\d{2})-(\d{2}-\d{2})\.dt$") {
                    $dateTimeString = "$($matches[1]) $($matches[2])"
                    return [datetime]::ParseExact($dateTimeString, "yyyy-MM-dd HH-mm", $null)
                }
                return [datetime]::MinValue
            } -Descending
    
            $filesToDelete = $sortedFiles | Select-Object -Skip $keepBackupCount
    
            foreach ($file in $filesToDelete) {
                Remove-Item -Path $file.FullName -Force
            }
        }
    }
}


function Remove-ParasiteRights {
    param (
        [string]$roleFileFullName
    )
  
    # Считаем исходный файл как текст
    $fileText = Get-Content -Raw -Encoding UTF8 $roleFileFullName

    # Определяем перенос строк в исходном файле (по первому совпадению)
    if ($fileText -match "`r`n") {
        $newLineChars = "`r`n"  # Windows style CRLF
    } elseif ($fileText -match "`r") {
        $newLineChars = "`r"    # Mac old style CR
    } elseif ($fileText -match "`n") {
        $newLineChars = "`n"    # Unix style LF
    } else {
        # По умолчанию ставим CRLF (можно и LF)
        $newLineChars = "`r`n"
    }

    [xml]$xml = $fileText

    # Создаем менеджер пространств имен и регистрируем префикс
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $nsMgr.AddNamespace("r", "http://v8.1c.ru/8.2/roles")

    # Удаляем все узлы <right>, у которых <value> равно "false"
    $rightNodes = $xml.SelectNodes("//r:object/r:right[r:value='false']", $nsMgr)
    
    # Если нет узлов для удаления - выходим
    if ($rightNodes.Count -eq 0) {
        return
    }

    foreach ($right in $rightNodes) {
        $right.ParentNode.RemoveChild($right) | Out-Null
    }

    # Удаляем все узлы <object>, у которых не осталось узлов <right>
    $objectNodes = $xml.SelectNodes("//r:object[not(r:right)]", $nsMgr)
    foreach ($object in $objectNodes) {
        $object.ParentNode.RemoveChild($object) | Out-Null
    }

    # Настройки XmlWriter с переносами строк из исходного файла
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "`t"
    $settings.NewLineChars = $newLineChars
    $settings.NewLineHandling = "Replace"

    $writer = [System.Xml.XmlWriter]::Create($roleFileFullName, $settings)
    $xml.Save($writer)
    $writer.Close()
}


function Optimize-RoleSizes {
    param (
        [string]$sourcePath
    )
	
    # Ищем папки с именем Roles рекурсивно
    $rolesDirs = Get-ChildItem -Path $sourcePath -Directory -Recurse | Where-Object { $_.Name -eq 'Roles' }

    foreach ($dir in $rolesDirs) {
        # Ищем нужные файлы в каталоге Roles и его подкаталогах
        $files = Get-ChildItem -Path $dir.FullName -Recurse -File | Where-Object { $_.Name -in @('Rights.rights', 'Rights.xml') }

        foreach ($file in $files) {
            Remove-ParasiteRights -roleFileFullName $file.FullName
        }
    }

}
