# =================================================================
# Startup - Met a jour le repo gamingserver-config au demarrage
# =================================================================
# Configure comme script de demarrage GPO par setup.ps1

$repoPath = "C:\source\gamingserver-config"

if (Test-Path "$repoPath\.git") {
    git -C $repoPath pull --ff-only
}

# Monter le partage reseau pour le backup
$credFile = "$repoPath\network-credentials.cfg"
if (Test-Path $credFile) {
    $creds = Get-Content $credFile | ConvertFrom-StringData
    net use "\\HomeServer\Backup" /user:$($creds.username) $($creds.password) /persistent:yes 2>&1 | Out-Null
}
