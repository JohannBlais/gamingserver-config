# =================================================================
# Startup - Met a jour le repo gamingserver-config au demarrage
# =================================================================
# Configure comme script de demarrage GPO par setup.ps1

$repoPath = "C:\source\gamingserver-config"

if (Test-Path "$repoPath\.git") {
    git -C $repoPath pull --ff-only
}

# Synchroniser la config HASS.Agent si elle a change dans le repo.
# Limite aux fichiers sans secret (commands.json, sensors.json) ;
# servicemqttsettings.json et servicesettings.json contiennent des
# placeholders dans le repo et doivent etre laisses tels quels en local.
$hassAgentConfigDest = "C:\Program Files (x86)\LAB02 Research\HASS.Agent Satellite Service\config"
$configSource = Join-Path $repoPath "HASS.Agent\config"
if (Test-Path $hassAgentConfigDest) {
    $changed = $false
    foreach ($file in @("commands.json", "sensors.json")) {
        $src = Join-Path $configSource $file
        $dst = Join-Path $hassAgentConfigDest $file
        if (-not (Test-Path $src)) { continue }
        $srcHash = (Get-FileHash -Path $src -Algorithm SHA256).Hash
        $dstHash = if (Test-Path $dst) { (Get-FileHash -Path $dst -Algorithm SHA256).Hash } else { "" }
        if ($srcHash -ne $dstHash) {
            Copy-Item -Path $src -Destination $dst -Force
            $changed = $true
        }
    }
    if ($changed) {
        $svc = Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*HASS.Agent*" } |
            Select-Object -First 1
        if ($svc) { Restart-Service -Name $svc.Name -Force }
    }
}

# Monter le partage reseau pour le backup
$credFile = "$repoPath\network-credentials.cfg"
if (Test-Path $credFile) {
    $creds = Get-Content $credFile | ConvertFrom-StringData
    net use "\\HomeServer\Backup" /user:$($creds.username) $($creds.password) /persistent:yes 2>&1 | Out-Null
}
