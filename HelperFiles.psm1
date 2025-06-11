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