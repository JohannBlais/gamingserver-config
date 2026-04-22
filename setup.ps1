# =================================================================
# Setup Enshrouded Dedicated Server - Machine Windows
# =================================================================
# Script modulaire avec menu interactif.
# Scenarios disponibles :
#   1. Installation complete initiale
#   2. Mise a jour des composants (SteamCMD, Enshrouded, NSSM, MQTTnet)
#   3. Actions individuelles (sous-menu)
#
# Executer en tant qu'administrateur :
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\setup.ps1
# =================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot

$steamCmdPath = "C:\SteamCMD"
$serverPath = "C:\SteamApps\EnshroudedServer"
$enshroudedAppId = 2278520

# =================================================================
# FONCTIONS UTILITAIRES
# =================================================================

function Stop-ServiceIfRunning($name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "Arret du service $name..." -ForegroundColor Yellow
        nssm stop $name | Out-Null
        return $true
    }
    return $false
}

function Start-ServiceIfWasRunning($name, $wasRunning) {
    if ($wasRunning) {
        Write-Host "Redemarrage du service $name..." -ForegroundColor Yellow
        nssm start $name | Out-Null
    }
}

function Write-MQTTnetDll($libDir, $mqttnetDll) {
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

# =================================================================
# FONCTIONS INSTALLATION / CONFIGURATION
# =================================================================

function Set-PowerShellPolicy {
    Write-Host "`n=== Politique d'execution PowerShell ===" -ForegroundColor Cyan
    Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    Write-Host "Politique d'execution definie sur RemoteSigned" -ForegroundColor Green
}

function Install-SteamCMD {
    Write-Host "`n=== Installation SteamCMD ===" -ForegroundColor Cyan
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
}

function Update-SteamCMD {
    Write-Host "`n=== Mise a jour SteamCMD ===" -ForegroundColor Cyan
    if (-not (Test-Path "$steamCmdPath\steamcmd.exe")) {
        Install-SteamCMD
        return
    }
    Write-Host "Lancement de SteamCMD pour auto-update..."
    & "$steamCmdPath\steamcmd.exe" +quit
    Write-Host "SteamCMD a jour" -ForegroundColor Green
}

function Update-EnshroudedServer {
    Write-Host "`n=== Installation/Mise a jour Enshrouded Dedicated Server ===" -ForegroundColor Cyan

    if (-not (Test-Path "$steamCmdPath\steamcmd.exe")) {
        Write-Host "ERREUR : SteamCMD n'est pas installe. Installer SteamCMD d'abord." -ForegroundColor Red
        return
    }

    $wasRunning = Stop-ServiceIfRunning "EnshroudedServer"

    Write-Host "Telechargement/mise a jour (app $enshroudedAppId)..."
    & "$steamCmdPath\steamcmd.exe" `
        +force_install_dir $serverPath `
        +login anonymous `
        +app_update $enshroudedAppId validate `
        +quit

    if (Test-Path "$serverPath\enshrouded_server.exe") {
        Write-Host "Enshrouded Dedicated Server installe dans $serverPath" -ForegroundColor Green
    } else {
        Write-Host "ERREUR : enshrouded_server.exe introuvable apres installation" -ForegroundColor Red
    }

    Start-ServiceIfWasRunning "EnshroudedServer" $wasRunning
}

function Install-NSSM {
    Write-Host "`n=== Installation NSSM ===" -ForegroundColor Cyan
    $nssmInstalled = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmInstalled) {
        Write-Host "NSSM deja installe" -ForegroundColor Yellow
    } else {
        Write-Host "Installation de NSSM via winget..."
        winget install NSSM.NSSM --source winget --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Host "NSSM installe" -ForegroundColor Green
    }
}

function Update-NSSM {
    Write-Host "`n=== Mise a jour NSSM ===" -ForegroundColor Cyan
    $nssmInstalled = Get-Command nssm -ErrorAction SilentlyContinue
    if (-not $nssmInstalled) {
        Install-NSSM
        return
    }
    winget upgrade NSSM.NSSM --source winget --accept-source-agreements --accept-package-agreements
    Write-Host "NSSM a jour" -ForegroundColor Green
}

function New-EnshroudedService {
    Write-Host "`n=== Creation du service EnshroudedServer ===" -ForegroundColor Cyan
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
    $backupBat = Join-Path $scriptDir "run-backup.bat"
    nssm set EnshroudedServer AppEvents Exit/Post $backupBat
    Write-Host "Service configure (auto-start, arret propre 30s, backup post-arret)" -ForegroundColor Green
}

function Disable-FastStartup {
    Write-Host "`n=== Desactivation Fast Startup ===" -ForegroundColor Cyan
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "HiberbootEnabled" -Value 0
    Write-Host "Fast Startup desactive (registre + GPO)" -ForegroundColor Green
}

function Set-NetworkCredentials {
    Write-Host "`n=== Identifiants partage reseau ===" -ForegroundColor Cyan
    $credFile = Join-Path $scriptDir "network-credentials.cfg"
    if (Test-Path $credFile) {
        Write-Host "Fichier credentials deja present" -ForegroundColor Yellow
        $redo = Read-Host "Remplacer ? (O/N)"
        if ($redo -ne "O" -and $redo -ne "o") { return }
    }
    $networkUser = Read-Host "Utilisateur du partage \\HomeServer"
    $networkPass = Read-Host "Mot de passe" -AsSecureString
    $networkPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($networkPass))
    Set-Content -Path $credFile -Value "username=$networkUser`npassword=$networkPassPlain"
    $networkPassPlain = $null
    Write-Host "Identifiants stockes dans $credFile" -ForegroundColor Green
}

function Register-GpoScripts {
    Write-Host "`n=== Enregistrement scripts GPO ===" -ForegroundColor Cyan
    & (Join-Path $scriptDir "register-gpo-scripts.ps1")
}

function Copy-HassAgentConfig {
    Write-Host "`n=== HASS.Agent Satellite Service ===" -ForegroundColor Cyan
    $hassAgentConfigDest = "C:\Program Files (x86)\LAB02 Research\HASS.Agent Satellite Service\config"
    if (Test-Path $hassAgentConfigDest) {
        $configSource = Join-Path $scriptDir "HASS.Agent\config"
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
}

function Install-MQTTnet {
    Write-Host "`n=== Installation MQTTnet ===" -ForegroundColor Cyan
    $libDir = Join-Path $scriptDir "lib"
    $mqttnetDll = Join-Path $libDir "MQTTnet.dll"
    if (Test-Path $mqttnetDll) {
        Write-Host "MQTTnet.dll deja present" -ForegroundColor Yellow
    } else {
        Write-MQTTnetDll $libDir $mqttnetDll
    }
}

function Update-MQTTnet {
    Write-Host "`n=== Mise a jour MQTTnet ===" -ForegroundColor Cyan

    $wasRunning = Stop-ServiceIfRunning "EnshroudedMonitor"

    $libDir = Join-Path $scriptDir "lib"
    $mqttnetDll = Join-Path $libDir "MQTTnet.dll"
    if (Test-Path $mqttnetDll) {
        Remove-Item $mqttnetDll -Force
        Write-Host "Ancienne DLL supprimee" -ForegroundColor Yellow
    }
    Write-MQTTnetDll $libDir $mqttnetDll

    Start-ServiceIfWasRunning "EnshroudedMonitor" $wasRunning
}

function New-MonitorService {
    Write-Host "`n=== Service EnshroudedMonitor ===" -ForegroundColor Cyan
    $monitorServiceExists = nssm status EnshroudedMonitor 2>&1
    if ($monitorServiceExists -match "SERVICE_") {
        Write-Host "Le service EnshroudedMonitor existe deja" -ForegroundColor Yellow
    } else {
        nssm install EnshroudedMonitor "powershell.exe"
        Write-Host "Service EnshroudedMonitor cree" -ForegroundColor Green
    }
    $monitorScript = Join-Path $scriptDir "monitor-enshrouded-log.ps1"
    nssm set EnshroudedMonitor AppDirectory $scriptDir
    nssm set EnshroudedMonitor AppParameters "-ExecutionPolicy Bypass -File `"$monitorScript`""
    nssm set EnshroudedMonitor DisplayName "Enshrouded Log Monitor"
    nssm set EnshroudedMonitor Description "Monitore les logs Enshrouded et publie sur MQTT"
    nssm set EnshroudedMonitor Start SERVICE_AUTO_START
    nssm set EnshroudedMonitor DependOnService EnshroudedServer
    Write-Host "Service configure (auto-start, depend de EnshroudedServer)" -ForegroundColor Green
}

function Update-MonitorScript {
    Write-Host "`n=== Mise a jour du script de monitoring ===" -ForegroundColor Cyan

    $gitDir = Join-Path $scriptDir ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Host "ERREUR : $scriptDir n'est pas un repo git" -ForegroundColor Red
        return
    }

    Write-Host "git pull dans $scriptDir..."
    Push-Location $scriptDir
    try {
        git pull --ff-only
    } finally {
        Pop-Location
    }

    $wasRunning = Stop-ServiceIfRunning "EnshroudedMonitor"
    if (-not $wasRunning) {
        Write-Host "Service EnshroudedMonitor n'etait pas en cours, demarrage..." -ForegroundColor Yellow
    }
    nssm start EnshroudedMonitor | Out-Null
    Write-Host "Service EnshroudedMonitor demarre" -ForegroundColor Green
}

function Start-EnshroudedServerPrompt {
    Write-Host "`n=== Demarrage du serveur ===" -ForegroundColor Cyan
    $startNow = Read-Host "Demarrer le serveur Enshrouded maintenant ? (O/N)"
    if ($startNow -eq "O" -or $startNow -eq "o") {
        nssm start EnshroudedServer
        Write-Host "Serveur Enshrouded demarre" -ForegroundColor Green
    }
}

function Show-Summary {
    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "  Setup termine !" -ForegroundColor Green
    Write-Host "  - Enshrouded Server : $serverPath" -ForegroundColor White
    Write-Host "  - Service NSSM : EnshroudedServer (auto-start)" -ForegroundColor White
    Write-Host "  - Service NSSM : EnshroudedMonitor (auto-start, MQTT)" -ForegroundColor White
    Write-Host "  - Fast Startup : desactive" -ForegroundColor White
    Write-Host "  - Backup : a chaque arret de Windows" -ForegroundColor White
    Write-Host "  - HASS.Agent : configuration manuelle" -ForegroundColor White
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "`nRedemarrer la machine pour activer le Wake-on-LAN." -ForegroundColor Yellow
}

# =================================================================
# SCENARIOS
# =================================================================

function Invoke-FullSetup {
    Write-Host "`n### Installation complete initiale ###" -ForegroundColor Magenta
    Set-PowerShellPolicy
    Install-SteamCMD
    Update-EnshroudedServer
    Install-NSSM
    New-EnshroudedService
    Disable-FastStartup
    Set-NetworkCredentials
    Register-GpoScripts
    Copy-HassAgentConfig
    Install-MQTTnet
    New-MonitorService
    Start-EnshroudedServerPrompt
    Show-Summary
}

function Invoke-UpdateComponents {
    Write-Host "`n### Mise a jour des composants ###" -ForegroundColor Magenta
    Update-SteamCMD
    Update-EnshroudedServer
    Update-NSSM
    Update-MQTTnet
    Write-Host "`n### Mise a jour terminee ###" -ForegroundColor Green
}

# =================================================================
# MENUS
# =================================================================

function Show-IndividualMenu {
    while ($true) {
        Write-Host "`n=====================================================" -ForegroundColor Cyan
        Write-Host "  Actions individuelles" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "  1. Mettre a jour Enshrouded Server"
        Write-Host "  2. Mettre a jour SteamCMD"
        Write-Host "  3. Mettre a jour NSSM"
        Write-Host "  4. Mettre a jour MQTTnet"
        Write-Host "  5. Reconfigurer HASS.Agent"
        Write-Host "  6. Recreer le service EnshroudedServer"
        Write-Host "  7. Recreer le service EnshroudedMonitor"
        Write-Host "  8. Mettre a jour les identifiants partage reseau"
        Write-Host "  9. Mise a jour du script de monitoring (git pull + restart)"
        Write-Host "  R. Retour au menu principal"
        $choice = Read-Host "`nChoix"
        switch ($choice.ToUpper()) {
            "1" { Update-EnshroudedServer }
            "2" { Update-SteamCMD }
            "3" { Update-NSSM }
            "4" { Update-MQTTnet }
            "5" { Copy-HassAgentConfig }
            "6" { New-EnshroudedService }
            "7" { New-MonitorService }
            "8" { Set-NetworkCredentials }
            "9" { Update-MonitorScript }
            "R" { return }
            default { Write-Host "Choix invalide" -ForegroundColor Red }
        }
    }
}

function Show-MainMenu {
    while ($true) {
        Write-Host "`n=====================================================" -ForegroundColor Cyan
        Write-Host "  Setup Enshrouded Dedicated Server" -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "  1. Installation complete initiale"
        Write-Host "  2. Mise a jour des composants (SteamCMD, Enshrouded, NSSM, MQTTnet)"
        Write-Host "  3. Mise a jour du script de monitoring (git pull + restart)"
        Write-Host "  4. Actions individuelles..."
        Write-Host "  Q. Quitter"
        $choice = Read-Host "`nChoix"
        switch ($choice.ToUpper()) {
            "1" { Invoke-FullSetup }
            "2" { Invoke-UpdateComponents }
            "3" { Update-MonitorScript }
            "4" { Show-IndividualMenu }
            "Q" { return }
            default { Write-Host "Choix invalide" -ForegroundColor Red }
        }
    }
}

# =================================================================
# MAIN
# =================================================================

Show-MainMenu
