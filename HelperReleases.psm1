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