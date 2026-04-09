# ═══════════════════════════════════════════════════════════════
# Enregistre les scripts GPO de démarrage et d'arrêt
# ═══════════════════════════════════════════════════════════════
# Crée des wrappers dans le dossier GPO qui appellent les scripts
# du repo. Peut être relancé après un déplacement du repo.
#
# Usage :
#   .\register-gpo-scripts.ps1
# ═══════════════════════════════════════════════════════════════

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$gpoScriptsDir = "C:\Windows\System32\GroupPolicy\Machine\Scripts"
$gpoStartupDir = "$gpoScriptsDir\Startup"
$gpoShutdownDir = "$gpoScriptsDir\Shutdown"

Write-Host "`n=== Enregistrement des scripts GPO ===" -ForegroundColor Cyan

# Configurer le timeout des scripts GPO à 300 secondes
$gpoScriptsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
New-Item -Path $gpoScriptsPath -Force | Out-Null
Set-ItemProperty -Path $gpoScriptsPath -Name "MaxGPOScriptWait" -Value 300

Write-Host "Timeout scripts GPO configuré à 300 secondes" -ForegroundColor Green

# Créer les dossiers GPO si nécessaire
New-Item -ItemType Directory -Path $gpoStartupDir -Force | Out-Null
New-Item -ItemType Directory -Path $gpoShutdownDir -Force | Out-Null

# Wrapper startup (appelle le script du repo)
$startupScript = Join-Path $PSScriptRoot "startup.ps1"
if (-not (Test-Path $startupScript)) {
    Write-Host "ATTENTION : startup.ps1 introuvable dans le repo" -ForegroundColor Red
} else {
    Set-Content -Path "$gpoStartupDir\startup.ps1" -Value "& '$startupScript'"
    Write-Host "Wrapper startup créé → $startupScript" -ForegroundColor Green
}

# Wrapper shutdown (appelle le script du repo)
$shutdownScript = Join-Path $PSScriptRoot "shutdown.ps1"
if (-not (Test-Path $shutdownScript)) {
    Write-Host "ATTENTION : shutdown.ps1 introuvable dans le repo" -ForegroundColor Red
} else {
    Set-Content -Path "$gpoShutdownDir\shutdown.ps1" -Value "& '$shutdownScript'"
    Write-Host "Wrapper shutdown créé → $shutdownScript" -ForegroundColor Green
}

# Enregistrer les scripts dans le registre GPO
$gpoRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts"

# Startup
$startupRegPath = "$gpoRegPath\Startup\0\0"
New-Item -Path $startupRegPath -Force | Out-Null
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "GPO-ID" -Value "LocalGPO"
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "SOM-ID" -Value "Local"
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "FileSysPath" -Value "C:\Windows\System32\GroupPolicy\Machine"
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "DisplayName" -Value "Local Group Policy"
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "GPOName" -Value "Local Group Policy"
Set-ItemProperty -Path "$gpoRegPath\Startup\0" -Name "PSScriptOrder" -Value 1
Set-ItemProperty -Path $startupRegPath -Name "Script" -Value "startup.ps1"
Set-ItemProperty -Path $startupRegPath -Name "Parameters" -Value ""
Set-ItemProperty -Path $startupRegPath -Name "IsPowershell" -Value 1
Set-ItemProperty -Path $startupRegPath -Name "ExecTime" -Value 0

# Shutdown
$shutdownRegPath = "$gpoRegPath\Shutdown\0\0"
New-Item -Path $shutdownRegPath -Force | Out-Null
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "GPO-ID" -Value "LocalGPO"
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "SOM-ID" -Value "Local"
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "FileSysPath" -Value "C:\Windows\System32\GroupPolicy\Machine"
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "DisplayName" -Value "Local Group Policy"
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "GPOName" -Value "Local Group Policy"
Set-ItemProperty -Path "$gpoRegPath\Shutdown\0" -Name "PSScriptOrder" -Value 1
Set-ItemProperty -Path $shutdownRegPath -Name "Script" -Value "shutdown.ps1"
Set-ItemProperty -Path $shutdownRegPath -Name "Parameters" -Value ""
Set-ItemProperty -Path $shutdownRegPath -Name "IsPowershell" -Value 1
Set-ItemProperty -Path $shutdownRegPath -Name "ExecTime" -Value 0

# Dupliquer dans State\Machine pour que gpedit les affiche
$stateStartupPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0\0"
New-Item -Path $stateStartupPath -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "GPO-ID" -Value "LocalGPO"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "SOM-ID" -Value "Local"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "FileSysPath" -Value "C:\Windows\System32\GroupPolicy\Machine"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "DisplayName" -Value "Local Group Policy"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "GPOName" -Value "Local Group Policy"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Startup\0" -Name "PSScriptOrder" -Value 1
Set-ItemProperty -Path $stateStartupPath -Name "Script" -Value "startup.ps1"
Set-ItemProperty -Path $stateStartupPath -Name "Parameters" -Value ""
Set-ItemProperty -Path $stateStartupPath -Name "IsPowershell" -Value 1
Set-ItemProperty -Path $stateStartupPath -Name "ExecTime" -Value 0

$stateShutdownPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0\0"
New-Item -Path $stateShutdownPath -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "GPO-ID" -Value "LocalGPO"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "SOM-ID" -Value "Local"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "FileSysPath" -Value "C:\Windows\System32\GroupPolicy\Machine"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "DisplayName" -Value "Local Group Policy"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "GPOName" -Value "Local Group Policy"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Scripts\Shutdown\0" -Name "PSScriptOrder" -Value 1
Set-ItemProperty -Path $stateShutdownPath -Name "Script" -Value "shutdown.ps1"
Set-ItemProperty -Path $stateShutdownPath -Name "Parameters" -Value ""
Set-ItemProperty -Path $stateShutdownPath -Name "IsPowershell" -Value 1
Set-ItemProperty -Path $stateShutdownPath -Name "ExecTime" -Value 0

Write-Host "Scripts GPO enregistrés dans le registre" -ForegroundColor Green
