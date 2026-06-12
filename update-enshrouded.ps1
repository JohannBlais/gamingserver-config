# =============================================================================
# Update Enshrouded Dedicated Server
# Declenche par le bouton HASS.Agent (MQTT) ou manuellement.
# Arrete les services, met a jour via SteamCMD, puis restaure l'etat precedent.
# Log dans update.log (meme pattern que monitor.log / backup.log).
# =============================================================================

$ErrorActionPreference = "Stop"

$scriptDir       = $PSScriptRoot
$steamCmdPath    = "C:\SteamCMD"
$serverPath      = "C:\SteamApps\EnshroudedServer"
$enshroudedAppId = 2278520
$logFile         = Join-Path $scriptDir "update.log"
$lockFile        = Join-Path $scriptDir "update.lock"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Stop-ServiceIfRunning($name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Log "Arret du service $name..."
        Stop-Service -Name $name -Force -ErrorAction Stop
        return $true
    }
    return $false
}

function Start-ServiceSafe($name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        Log "Demarrage du service $name..."
        Start-Service -Name $name -ErrorAction Stop
    }
}

# --- Verrou anti-concurrence ---
# Evite que deux clics sur le bouton lancent deux mises a jour en parallele.
# Un verrou de plus de 30 min est considere comme perime (crash precedent).
if (Test-Path $lockFile) {
    $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime
    if ($age.TotalMinutes -lt 30) {
        Log "Mise a jour deja en cours (verrou recent : $lockFile). Abandon."
        exit 1
    }
    Log "Verrou perime detecte (>30 min), suppression et poursuite."
    Remove-Item $lockFile -Force
}
New-Item -ItemType File -Path $lockFile -Force | Out-Null

try {
    Log "=== Debut mise a jour Enshrouded Server ==="

    if (-not (Test-Path "$steamCmdPath\steamcmd.exe")) {
        throw "SteamCMD introuvable dans $steamCmdPath"
    }

    # Arret des services (monitor avant serveur a cause de la dependance).
    # On memorise si le serveur tournait pour restaurer l'etat ensuite.
    Stop-ServiceIfRunning "EnshroudedMonitor" | Out-Null
    $serverWasRunning = Stop-ServiceIfRunning "EnshroudedServer"

    # Mise a jour via SteamCMD
    Log "Lancement de SteamCMD (app $enshroudedAppId)..."
    & "$steamCmdPath\steamcmd.exe" `
        +force_install_dir $serverPath `
        +login anonymous `
        +app_update $enshroudedAppId validate `
        +quit
    Log "SteamCMD termine (code $LASTEXITCODE)"

    if (Test-Path "$serverPath\enshrouded_server.exe") {
        Log "Mise a jour OK : enshrouded_server.exe present"
    } else {
        Log "ERREUR : enshrouded_server.exe introuvable apres mise a jour"
    }

    # Restaurer l'etat : redemarrer seulement si le serveur tournait avant.
    if ($serverWasRunning) {
        Start-ServiceSafe "EnshroudedServer"
        Start-ServiceSafe "EnshroudedMonitor"
    } else {
        Log "Le serveur etait arrete avant la mise a jour, il reste arrete."
    }

    Log "=== Mise a jour terminee ==="
}
catch {
    Log "ERREUR : $_"
}
finally {
    Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
}
