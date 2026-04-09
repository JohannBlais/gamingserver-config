# =================================================================
# Init - Installe Git et clone le repo gamingserver-config
# =================================================================
# Executer en tant qu'administrateur :
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   irm https://raw.githubusercontent.com/JohannBlais/gamingserver-config/main/init.ps1 | iex
# =================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$repoUrl = "https://github.com/JohannBlais/gamingserver-config.git"
$repoPath = "C:\source\gamingserver-config"

# --- 1. Installation Git ------------------------------------

Write-Host "`n=== Installation Git ===" -ForegroundColor Cyan

$gitInstalled = Get-Command git -ErrorAction SilentlyContinue
if ($gitInstalled) {
    Write-Host "Git deja installe" -ForegroundColor Yellow
} else {
    Write-Host "Installation de Git via winget..."
    winget install Git.Git --source winget --accept-source-agreements --accept-package-agreements
    # Rafraichir le PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "Git installe" -ForegroundColor Green
}

# --- 2. Cloner le repo --------------------------------------

Write-Host "`n=== Clonage du repo ===" -ForegroundColor Cyan

if (Test-Path "$repoPath\.git") {
    Write-Host "Repo deja clone dans $repoPath, mise a jour..." -ForegroundColor Yellow
    git -C $repoPath pull
} else {
    git clone $repoUrl $repoPath
}

Write-Host "Repo pret dans $repoPath" -ForegroundColor Green

# --- Etape suivante -----------------------------------------

Write-Host "`n===================================================" -ForegroundColor Cyan
Write-Host "  Pour lancer le setup complet :" -ForegroundColor White
Write-Host "  cd $repoPath" -ForegroundColor White
Write-Host "  .\setup.ps1" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Cyan
