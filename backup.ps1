# Backup Enshrouded Server - saves + config
# Déclenché par NSSM AppEvents Exit/Post via run-backup.bat

$serverPath = "C:\SteamApps\EnshroudedServer"
$backupDest = "\\HomeServer\Backup\Enshrouded Server"
$retention = 30
$logFile = "C:\source\gamingserver-config\backup.log"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$zipName = "enshrouded_backup_$timestamp.zip"
$zipPath = "$env:TEMP\$zipName"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Log "=== Début du backup ==="

# Monter le partage réseau avec les credentials
$credFile = "C:\source\gamingserver-config\network-credentials.cfg"
if (Test-Path $credFile) {
    $creds = Get-Content $credFile | ConvertFrom-StringData
    Log "Connexion au partage réseau..."
    net use "\\HomeServer\Backup" /user:$($creds.username) $($creds.password) 2>&1 | Out-Null
    Log "Partage réseau connecté"
} else {
    Log "ATTENTION : fichier credentials introuvable ($credFile)"
}

$filesToBackup = @(
    "$serverPath\savegame",
    "$serverPath\enshrouded_server.json"
)

try {
    Log "Compression des fichiers..."
    Compress-Archive -Path $filesToBackup -DestinationPath $zipPath -Force
    Log "Zip créé : $zipPath"

    Log "Copie vers $backupDest..."
    Copy-Item -Path $zipPath -Destination "$backupDest\$zipName" -Force
    Log "Backup copié : $zipName"

    Log "Nettoyage du zip temporaire..."
    Remove-Item -Path $zipPath -Force

    Log "Application de la rétention ($retention backups max)..."
    $removed = Get-ChildItem -Path $backupDest -Filter "enshrouded_backup_*.zip" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $retention
    if ($removed) {
        $removed | Remove-Item -Force
        Log "Supprimé : $($removed.Count) ancien(s) backup(s)"
    }

    Log "=== Backup terminé avec succès ==="
} catch {
    Log "ERREUR : $_"
}
