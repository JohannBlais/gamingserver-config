# Backup Enshrouded Server - saves + config
# Déclenché par GPO à l'arrêt de Windows

$serverPath = "C:\SteamApps\EnshroudedServer"
$backupDest = "\\HomeServer\Backup\Enshrouded Server"
$retention = 30
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$zipName = "enshrouded_backup_$timestamp.zip"
$zipPath = "$env:TEMP\$zipName"

# Compresser saves + config dans un zip
$filesToBackup = @(
    "$serverPath\savegame",
    "$serverPath\enshrouded_server.json"
)

Compress-Archive -Path $filesToBackup -DestinationPath $zipPath -Force

# Copier vers le partage réseau
Copy-Item -Path $zipPath -Destination "$backupDest\$zipName" -Force

# Nettoyer le zip temporaire
Remove-Item -Path $zipPath -Force

# Rétention : garder les 30 derniers backups
Get-ChildItem -Path $backupDest -Filter "enshrouded_backup_*.zip" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $retention |
    Remove-Item -Force
