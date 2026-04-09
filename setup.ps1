# =================================================================
# Setup Enshrouded Dedicated Server - Machine Windows
# =================================================================
# Ce script configure une machine Windows vierge pour faire
# tourner un serveur dedie Enshrouded avec :
#   - SteamCMD + Enshrouded Dedicated Server
#   - Service NSSM (demarrage auto, arret propre)
#   - HASS.Agent Satellite Service (monitoring MQTT)
#   - Wake-on-LAN (desactivation Fast Startup)
#   - Backup automatique a l'arret
#
# Executer en tant qu'administrateur :
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup.ps1
# =================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$steamCmdPath = "C:\SteamCMD"
$serverPath = "C:\SteamApps\EnshroudedServer"
$enshroudedAppId = 2278520

# --- 0. Politique d'execution PowerShell -----------------------

Write-Host "`n=== 0. Politique d'execution PowerShell ===" -ForegroundColor Cyan

Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Write-Host "Politique d'execution definie sur RemoteSigned" -ForegroundColor Green

# --- 1. Installation SteamCMD --------------------------------

Write-Host "`n=== 1. Installation SteamCMD ===" -ForegroundColor Cyan

if (Test-Path "$steamCmdPath\steamcmd.exe") {
    Write-Host "SteamCMD deja installe dans $steamCmdPath" -ForegroundColor Yellow
} else {
    Write-Host "Telechargement de SteamCMD..."
    New-Item -ItemType Directory -Path $steamCmdPath -Force | Out-Null
    $zipPath = "$env:TEMP\steamcmd.zip"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $steamCmdPath -Force
    Remove-Item -Path $zipPath -Force
    Write-Host "SteamCMD installe dans $steamCmdPath" -ForegroundColor Green
}

# --- 2. Installation Enshrouded Dedicated Server -------------

Write-Host "`n=== 2. Installation Enshrouded Dedicated Server ===" -ForegroundColor Cyan

Write-Host "Telechargement/mise a jour du serveur Enshrouded (app $enshroudedAppId)..."
& "$steamCmdPath\steamcmd.exe" `
    +force_install_dir $serverPath `
    +login anonymous `
    +app_update $enshroudedAppId validate `
    +quit

if (Test-Path "$serverPath\enshrouded_server.exe") {
    Write-Host "Enshrouded Dedicated Server installe dans $serverPath" -ForegroundColor Green
} else {
    Write-Host "ERREUR : enshrouded_server.exe introuvable apres installation" -ForegroundColor Red
    exit 1
}

# --- 3. Installation NSSM ------------------------------------

Write-Host "`n=== 3. Installation NSSM ===" -ForegroundColor Cyan

$nssmInstalled = Get-Command nssm -ErrorAction SilentlyContinue
if ($nssmInstalled) {
    Write-Host "NSSM deja installe" -ForegroundColor Yellow
} else {
    Write-Host "Installation de NSSM via winget..."
    winget install NSSM.NSSM --source winget --accept-source-agreements --accept-package-agreements
    # Rafraichir le PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "NSSM installe" -ForegroundColor Green
}

# --- 4. Creation du service Enshrouded -----------------------

Write-Host "`n=== 4. Creation du service EnshroudedServer ===" -ForegroundColor Cyan

$serviceExists = nssm status EnshroudedServer 2>&1
if ($serviceExists -match "SERVICE_") {
    Write-Host "Le service EnshroudedServer existe deja" -ForegroundColor Yellow
} else {
    nssm install EnshroudedServer "$serverPath\enshrouded_server.exe"
    Write-Host "Service EnshroudedServer cree" -ForegroundColor Green
}

nssm set EnshroudedServer AppDirectory $serverPath
nssm set EnshroudedServer DisplayName "Enshrouded Dedicated Server"
nssm set EnshroudedServer Description "Serveur dedie Enshrouded"
nssm set EnshroudedServer Start SERVICE_AUTO_START
nssm set EnshroudedServer AppExit Default Exit
nssm set EnshroudedServer AppStopMethodConsole 30000
nssm set EnshroudedServer AppStopMethodWindow 30000
$backupBat = Join-Path $PSScriptRoot "run-backup.bat"
nssm set EnshroudedServer AppEvents Exit/Post $backupBat

Write-Host "Service configure (auto-start, arret propre 30s, backup post-arret)" -ForegroundColor Green

# --- 5. Desactivation Fast Startup (GPO) --------------------

Write-Host "`n=== 5. Desactivation Fast Startup ===" -ForegroundColor Cyan

# Cle directe
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0

# Cle GPO (resiste aux mises a jour Windows)
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "HiberbootEnabled" -Value 0

Write-Host "Fast Startup desactive (registre + GPO)" -ForegroundColor Green

# --- 6. Identifiants partage reseau (backup) ----------------

Write-Host "`n=== 6. Identifiants partage reseau ===" -ForegroundColor Cyan

$credFile = Join-Path $PSScriptRoot "network-credentials.cfg"
if (Test-Path $credFile) {
    Write-Host "Fichier credentials deja present" -ForegroundColor Yellow
} else {
    $networkUser = Read-Host "Utilisateur du partage \\HomeServer"
    $networkPass = Read-Host "Mot de passe" -AsSecureString
    $networkPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($networkPass))
    Set-Content -Path $credFile -Value "username=$networkUser`npassword=$networkPassPlain"
    $networkPassPlain = $null
    Write-Host "Identifiants stockes dans $credFile" -ForegroundColor Green
}

# --- 7. Enregistrement des scripts GPO (startup/shutdown) ----

& (Join-Path $PSScriptRoot "register-gpo-scripts.ps1")

# --- 8. HASS.Agent Satellite Service -------------------------

Write-Host "`n=== 8. HASS.Agent Satellite Service ===" -ForegroundColor Cyan

$hassAgentConfigDest = "C:\Program Files (x86)\LAB02 Research\HASS.Agent Satellite Service\config"

if (Test-Path $hassAgentConfigDest) {
    # Copier toutes les configs
    $configSource = Join-Path $PSScriptRoot "HASS.Agent\config"
    Copy-Item -Path "$configSource\*" -Destination $hassAgentConfigDest -Force
    Write-Host "Configs HASS.Agent copiees" -ForegroundColor Green

    Write-Host @"
  IMPORTANT : remplacer les placeholders dans les fichiers suivants :
  - $hassAgentConfigDest\servicemqttsettings.json
      <MQTT_USERNAME>  -> nom d'utilisateur Home Assistant
      <MQTT_PASSWORD>  -> mot de passe Home Assistant
  - $hassAgentConfigDest\servicesettings.json
      <HA_LONG_LIVED_TOKEN>  -> token cree dans HA (Profil > Jetons d'acces longue duree)
"@ -ForegroundColor Yellow
} else {
    Write-Host @"
  HASS.Agent non installe. Installation manuelle requise :
  1. Telecharger HASS.Agent depuis https://hassagent.readthedocs.io/
  2. Installer, puis relancer ce script pour copier les configs
  3. Remplacer les placeholders dans les fichiers de config (voir ci-dessus)
"@ -ForegroundColor Yellow
}

# --- 9. MQTTnet Library --------------------------------------

Write-Host "`n=== 9. MQTTnet Library ===" -ForegroundColor Cyan

$libDir = Join-Path $PSScriptRoot "lib"
$mqttnetDll = Join-Path $libDir "MQTTnet.dll"

if (Test-Path $mqttnetDll) {
    Write-Host "MQTTnet.dll deja present" -ForegroundColor Yellow
} else {
    Write-Host "Telechargement de MQTTnet..."
    New-Item -ItemType Directory -Path $libDir -Force | Out-Null
    $nupkgUrl = "https://www.nuget.org/api/v2/package/MQTTnet/4.3.7.1207"
    $nupkgPath = "$env:TEMP\mqttnet.zip"
    Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath
    $extractPath = "$env:TEMP\mqttnet_extract"
    Expand-Archive -Path $nupkgPath -DestinationPath $extractPath -Force
    $sourceDll = Get-ChildItem -Path $extractPath -Recurse -Filter "MQTTnet.dll" |
        Where-Object { $_.FullName -match "netstandard2\.0" } |
        Select-Object -First 1
    Copy-Item -Path $sourceDll.FullName -Destination $mqttnetDll
    Remove-Item -Path $nupkgPath, $extractPath -Recurse -Force
    Write-Host "MQTTnet.dll installe dans lib/" -ForegroundColor Green
}

# --- 10. Service EnshroudedMonitor ---------------------------

Write-Host "`n=== 10. Service EnshroudedMonitor ===" -ForegroundColor Cyan

$monitorServiceExists = nssm status EnshroudedMonitor 2>&1
if ($monitorServiceExists -match "SERVICE_") {
    Write-Host "Le service EnshroudedMonitor existe deja" -ForegroundColor Yellow
} else {
    nssm install EnshroudedMonitor "powershell.exe"
    Write-Host "Service EnshroudedMonitor cree" -ForegroundColor Green
}

$monitorScript = Join-Path $PSScriptRoot "monitor-enshrouded-log.ps1"
nssm set EnshroudedMonitor AppDirectory $PSScriptRoot
nssm set EnshroudedMonitor AppParameters "-ExecutionPolicy Bypass -File `"$monitorScript`""
nssm set EnshroudedMonitor DisplayName "Enshrouded Log Monitor"
nssm set EnshroudedMonitor Description "Monitore les logs Enshrouded et publie sur MQTT"
nssm set EnshroudedMonitor Start SERVICE_AUTO_START
nssm set EnshroudedMonitor DependOnService EnshroudedServer

Write-Host "Service configure (auto-start, depend de EnshroudedServer)" -ForegroundColor Green

# --- 11. Demarrage des services ------------------------------

Write-Host "`n=== 11. Demarrage du serveur ===" -ForegroundColor Cyan

$startNow = Read-Host "Demarrer le serveur Enshrouded maintenant ? (O/N)"
if ($startNow -eq "O" -or $startNow -eq "o") {
    nssm start EnshroudedServer
    Write-Host "Serveur Enshrouded demarre" -ForegroundColor Green
}

# --- Resume --------------------------------------------------

Write-Host "`n===================================================" -ForegroundColor Cyan
Write-Host "  Setup termine !" -ForegroundColor Green
Write-Host "  - Enshrouded Server : $serverPath" -ForegroundColor White
Write-Host "  - Service NSSM : EnshroudedServer (auto-start)" -ForegroundColor White
Write-Host "  - Service NSSM : EnshroudedMonitor (auto-start, MQTT)" -ForegroundColor White
Write-Host "  - Fast Startup : desactive" -ForegroundColor White
Write-Host "  - Backup : a chaque arret de Windows" -ForegroundColor White
Write-Host "  - HASS.Agent : configuration manuelle (voir etape 8)" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "`nRedemarrer la machine pour activer le Wake-on-LAN." -ForegroundColor Yellow
