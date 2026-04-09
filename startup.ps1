# ═══════════════════════════════════════════════════════════════
# Startup — Met à jour le repo gamingserver-config au démarrage
# ═══════════════════════════════════════════════════════════════
# Configuré comme script de démarrage GPO par setup.ps1

$repoPath = "C:\source\gamingserver-config"

if (Test-Path "$repoPath\.git") {
    git -C $repoPath pull --ff-only
}
