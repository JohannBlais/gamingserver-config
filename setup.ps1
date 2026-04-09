# ═══════════════════════════════════════════════════════════════
# Setup Enshrouded Dedicated Server — Machine Windows
# ═══════════════════════════════════════════════════════════════
# Ce script configure une machine Windows vierge pour faire
# tourner un serveur dédié Enshrouded avec :
#   - SteamCMD + Enshrouded Dedicated Server
#   - Service NSSM (démarrage auto, arrêt propre)
#   - HASS.Agent Satellite Service (monitoring MQTT)
#   - Wake-on-LAN (désactivation Fast Startup)
#   - Backup automatique à l'arrêt
#
# Exécuter en tant qu'administrateur :
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup.ps1
# ═══════════════════════════════════════════════════════════════

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$steamCmdPath = "C:\SteamCMD"
$serverPath = "C:\SteamApps\EnshroudedServer"
$enshroudedAppId = 2278520

# ─── 0. Politique d'exécution PowerShell ─────────────────────

Write-Host "`n=== 0. Politique d'exécution PowerShell ===" -ForegroundColor Cyan

Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Write-Host "Politique d'exécution définie sur RemoteSigned" -ForegroundColor Green

# ─── 1. Installation SteamCMD ────────────────────────────────

Write-Host "`n=== 1. Installation SteamCMD ===" -ForegroundColor Cyan

if (Test-Path "$steamCmdPath\steamcmd.exe") {
    Write-Host "SteamCMD déjà installé dans $steamCmdPath" -ForegroundColor Yellow
} else {
    Write-Host "Téléchargement de SteamCMD..."
    New-Item -ItemType Directory -Path $steamCmdPath -Force | Out-Null
    $zipPath = "$env:TEMP\steamcmd.zip"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $steamCmdPath -Force
    Remove-Item -Path $zipPath -Force
    Write-Host "SteamCMD installé dans $steamCmdPath" -ForegroundColor Green
}

# ─── 2. Installation Enshrouded Dedicated Server ─────────────

Write-Host "`n=== 2. Installation Enshrouded Dedicated Server ===" -ForegroundColor Cyan

Write-Host "Téléchargement/mise à jour du serveur Enshrouded (app $enshroudedAppId)..."
& "$steamCmdPath\steamcmd.exe" `
    +force_install_dir $serverPath `
    +login anonymous `
    +app_update $enshroudedAppId validate `
    +quit

if (Test-Path "$serverPath\enshrouded_server.exe") {
    Write-Host "Enshrouded Dedicated Server installé dans $serverPath" -ForegroundColor Green
} else {
    Write-Host "ERREUR : enshrouded_server.exe introuvable après installation" -ForegroundColor Red
    exit 1
}

# ─── 3. Installation NSSM ────────────────────────────────────

Write-Host "`n=== 3. Installation NSSM ===" -ForegroundColor Cyan

$nssmInstalled = Get-Command nssm -ErrorAction SilentlyContinue
if ($nssmInstalled) {
    Write-Host "NSSM déjà installé" -ForegroundColor Yellow
} else {
    Write-Host "Installation de NSSM via winget..."
    winget install NSSM.NSSM --source winget --accept-source-agreements --accept-package-agreements
    # Rafraîchir le PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "NSSM installé" -ForegroundColor Green
}

# ─── 4. Création du service Enshrouded ───────────────────────

Write-Host "`n=== 4. Création du service EnshroudedServer ===" -ForegroundColor Cyan

$serviceExists = nssm status EnshroudedServer 2>&1
if ($serviceExists -match "SERVICE_") {
    Write-Host "Le service EnshroudedServer existe déjà" -ForegroundColor Yellow
} else {
    nssm install EnshroudedServer "$serverPath\enshrouded_server.exe"
    Write-Host "Service EnshroudedServer créé" -ForegroundColor Green
}

nssm set EnshroudedServer AppDirectory $serverPath
nssm set EnshroudedServer DisplayName "Enshrouded Dedicated Server"
nssm set EnshroudedServer Description "Serveur dédié Enshrouded"
nssm set EnshroudedServer Start SERVICE_AUTO_START
nssm set EnshroudedServer AppRestartDelay 10000
nssm set EnshroudedServer AppStopMethodConsole 30000
nssm set EnshroudedServer AppStopMethodWindow 30000
$backupBat = Join-Path $PSScriptRoot "run-backup.bat"
nssm set EnshroudedServer AppEvents Exit/Post $backupBat

Write-Host "Service configuré (auto-start, arrêt propre 30s, backup post-arrêt)" -ForegroundColor Green

# ─── 5. Désactivation Fast Startup (GPO) ─────────────────────

Write-Host "`n=== 5. Désactivation Fast Startup ===" -ForegroundColor Cyan

# Clé directe
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0

# Clé GPO (résiste aux mises à jour Windows)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "HiberbootEnabled" -Value 0

Write-Host "Fast Startup désactivé (registre + GPO)" -ForegroundColor Green

# ─── 6. Identifiants partage réseau (backup) ────────────────

Write-Host "`n=== 6. Identifiants partage réseau ===" -ForegroundColor Cyan

$credFile = Join-Path $PSScriptRoot "network-credentials.cfg"
if (Test-Path $credFile) {
    Write-Host "Fichier credentials déjà présent" -ForegroundColor Yellow
} else {
    $networkUser = Read-Host "Utilisateur du partage \\HomeServer"
    $networkPass = Read-Host "Mot de passe" -AsSecureString
    $networkPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($networkPass))
    Set-Content -Path $credFile -Value "username=$networkUser`npassword=$networkPassPlain"
    $networkPassPlain = $null
    Write-Host "Identifiants stockés dans $credFile" -ForegroundColor Green
}

# ─── 7. Enregistrement des scripts GPO (startup/shutdown) ────

& (Join-Path $PSScriptRoot "register-gpo-scripts.ps1")

# ─── 8. HASS.Agent Satellite Service ─────────────────────────

Write-Host "`n=== 8. HASS.Agent Satellite Service ===" -ForegroundColor Cyan

$hassAgentConfigDest = "C:\Program Files (x86)\LAB02 Research\HASS.Agent Satellite Service\config"

if (Test-Path $hassAgentConfigDest) {
    # Copier toutes les configs
    $configSource = Join-Path $PSScriptRoot "HASS.Agent\config"
    Copy-Item -Path "$configSource\*" -Destination $hassAgentConfigDest -Force
    Write-Host "Configs HASS.Agent copiées" -ForegroundColor Green

    Write-Host @"
  IMPORTANT : remplacer les placeholders dans les fichiers suivants :
  - $hassAgentConfigDest\servicemqttsettings.json
      <MQTT_USERNAME>  → nom d'utilisateur Home Assistant
      <MQTT_PASSWORD>  → mot de passe Home Assistant
  - $hassAgentConfigDest\servicesettings.json
      <HA_LONG_LIVED_TOKEN>  → token créé dans HA (Profil → Jetons d'accès longue durée)
"@ -ForegroundColor Yellow
} else {
    Write-Host @"
  HASS.Agent non installé. Installation manuelle requise :
  1. Télécharger HASS.Agent depuis https://hassagent.readthedocs.io/
  2. Installer, puis relancer ce script pour copier les configs
  3. Remplacer les placeholders dans les fichiers de config (voir ci-dessus)
"@ -ForegroundColor Yellow
}

# ─── 9. Démarrage du service ─────────────────────────────────

Write-Host "`n=== 9. Démarrage du serveur ===" -ForegroundColor Cyan

$startNow = Read-Host "Démarrer le serveur Enshrouded maintenant ? (O/N)"
if ($startNow -eq "O" -or $startNow -eq "o") {
    nssm start EnshroudedServer
    Write-Host "Serveur Enshrouded démarré" -ForegroundColor Green
}

# ─── Résumé ──────────────────────────────────────────────────

Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setup terminé !" -ForegroundColor Green
Write-Host "  - Enshrouded Server : $serverPath" -ForegroundColor White
Write-Host "  - Service NSSM : EnshroudedServer (auto-start)" -ForegroundColor White
Write-Host "  - Fast Startup : désactivé" -ForegroundColor White
Write-Host "  - Backup : à chaque arrêt de Windows" -ForegroundColor White
Write-Host "  - HASS.Agent : configuration manuelle (voir étape 7)" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "`nRedémarrer la machine pour activer le Wake-on-LAN." -ForegroundColor Yellow
