# ═══════════════════════════════════════════════════════════════
# Enregistre les scripts GPO de démarrage et d'arrêt
# ═══════════════════════════════════════════════════════════════
# L'enregistrement GPO local ne peut pas être automatisé de
# manière fiable. Ce script configure le timeout et affiche
# les instructions pour l'enregistrement manuel via gpedit.
#
# Usage :
#   .\register-gpo-scripts.ps1
# ═══════════════════════════════════════════════════════════════

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "`n=== Configuration des scripts GPO ===" -ForegroundColor Cyan

# Configurer le timeout des scripts GPO à 300 secondes
$gpoScriptsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
New-Item -Path $gpoScriptsPath -Force | Out-Null
Set-ItemProperty -Path $gpoScriptsPath -Name "MaxGPOScriptWait" -Value 300

Write-Host "Timeout scripts GPO configuré à 300 secondes" -ForegroundColor Green

# Instructions manuelles
$startupScript = Join-Path $PSScriptRoot "startup.ps1"
$shutdownScript = Join-Path $PSScriptRoot "backup.ps1"

Write-Host @"

  Enregistrement manuel requis dans gpedit.msc :
  Configuration ordinateur > Parametres Windows > Scripts (demarrage/arret)

  1. Demarrage > onglet Scripts PowerShell > Ajouter :
     $startupScript

  2. Arret du systeme > onglet Scripts PowerShell > Ajouter :
     $shutdownScript

"@ -ForegroundColor Yellow

# Ouvrir gpedit
$openGpedit = Read-Host "Ouvrir gpedit.msc maintenant ? (O/N)"
if ($openGpedit -eq "O" -or $openGpedit -eq "o") {
    gpedit.msc
}
