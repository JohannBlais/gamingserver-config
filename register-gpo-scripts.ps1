# ═══════════════════════════════════════════════════════════════
# Enregistre les scripts GPO de démarrage et d'arrêt
# ═══════════════════════════════════════════════════════════════
# Peut être relancé indépendamment pour mettre à jour les chemins
# après un déplacement du repo.
#
# Usage :
#   .\register-gpo-scripts.ps1
# ═══════════════════════════════════════════════════════════════

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "`n=== Enregistrement des scripts GPO ===" -ForegroundColor Cyan

# Configurer le timeout des scripts GPO à 300 secondes
$gpoScriptsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
New-Item -Path $gpoScriptsPath -Force | Out-Null
Set-ItemProperty -Path $gpoScriptsPath -Name "MaxGPOScriptWait" -Value 300

Write-Host "Timeout scripts GPO configuré à 300 secondes" -ForegroundColor Green

# Enregistrer le script d'arrêt (backup)
$shutdownScript = Join-Path $PSScriptRoot "shutdown.ps1"
if (-not (Test-Path $shutdownScript)) {
    Write-Host "ATTENTION : shutdown.ps1 introuvable dans le repo" -ForegroundColor Red
} else {
    $gpoShutdownPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0\0"
    New-Item -Path $gpoShutdownPath -Force | Out-Null
    Set-ItemProperty -Path $gpoShutdownPath -Name "Script" -Value $shutdownScript
    Set-ItemProperty -Path $gpoShutdownPath -Name "Parameters" -Value ""
    Set-ItemProperty -Path $gpoShutdownPath -Name "IsPowershell" -Value 1
    Set-ItemProperty -Path $gpoShutdownPath -Name "ExecTime" -Value 0
    Write-Host "Script d'arrêt enregistré : $shutdownScript" -ForegroundColor Green
}

# Enregistrer le script de démarrage (git pull)
$startupScript = Join-Path $PSScriptRoot "startup.ps1"
if (-not (Test-Path $startupScript)) {
    Write-Host "ATTENTION : startup.ps1 introuvable dans le repo" -ForegroundColor Red
} else {
    $gpoStartupPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0\0"
    New-Item -Path $gpoStartupPath -Force | Out-Null
    Set-ItemProperty -Path $gpoStartupPath -Name "Script" -Value $startupScript
    Set-ItemProperty -Path $gpoStartupPath -Name "Parameters" -Value ""
    Set-ItemProperty -Path $gpoStartupPath -Name "IsPowershell" -Value 1
    Set-ItemProperty -Path $gpoStartupPath -Name "ExecTime" -Value 0
    Write-Host "Script de démarrage enregistré : $startupScript" -ForegroundColor Green
}
