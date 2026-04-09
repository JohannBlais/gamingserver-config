# ═══════════════════════════════════════════════════════════════
# Startup — Met à jour le repo gamingserver-config au démarrage
# ═══════════════════════════════════════════════════════════════
# Configuré comme script de démarrage GPO par setup.ps1

$repoPath = "C:\source\gamingserver-config"

if (Test-Path "$repoPath\.git") {
    git -C $repoPath pull --ff-only
}

# Monter le partage réseau pour le backup
$credFile = "$repoPath\network-credentials.cfg"
if (Test-Path $credFile) {
    $creds = Get-Content $credFile | ConvertFrom-StringData
    net use "\\HomeServer\Backup" /user:$($creds.username) $($creds.password) /persistent:yes 2>&1 | Out-Null
}
