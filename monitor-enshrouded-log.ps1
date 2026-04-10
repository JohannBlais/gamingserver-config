# =============================================================================
# Enshrouded Server Log Monitor
# Parse les logs du serveur Enshrouded et publie les donnees sur MQTT
# pour integration Home Assistant (auto-discovery)
# =============================================================================

$ErrorActionPreference = "Continue"

$scriptDir = $PSScriptRoot

# --- Configuration ---
$serverPath      = "C:\SteamApps\EnshroudedServer"
$logPath         = "$serverPath\logs\enshrouded_server.log"
$monitorLogFile  = "C:\source\gamingserver-config\monitor.log"
$mqttConfigPath  = "C:\Program Files (x86)\LAB02 Research\HASS.Agent Satellite Service\config\servicemqttsettings.json"
$mqttnetDllPath  = Join-Path $scriptDir "lib\MQTTnet.dll"
$pollInterval    = 5
$topicPrefix     = "enshrouded"

# --- Fonction de log (meme pattern que backup.ps1) ---
function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Write-Host $line
    Add-Content -Path $monitorLogFile -Value $line
}

# --- Chargement MQTTnet ---
function Load-MqttNet {
    if (-not (Test-Path $mqttnetDllPath)) {
        throw "MQTTnet.dll introuvable dans $mqttnetDllPath. Lancer setup.ps1 d'abord."
    }
    Add-Type -Path $mqttnetDllPath
    Log "MQTTnet charge"
}

# --- Lecture config MQTT depuis HASS.Agent ---
function Get-MqttConfig {
    if (-not (Test-Path $mqttConfigPath)) {
        throw "Config MQTT introuvable : $mqttConfigPath"
    }
    $config = Get-Content $mqttConfigPath -Raw | ConvertFrom-Json
    return @{
        Broker   = $config.MqttAddress
        Port     = $config.MqttPort
        Username = $config.MqttUsername
        Password = $config.MqttPassword
        DiscoveryPrefix = $config.MqttDiscoveryPrefix
    }
}

# --- Connexion MQTT avec LWT ---
function Connect-Mqtt {
    $config = Get-MqttConfig

    $factory = [MQTTnet.MqttFactory]::new()
    $client = $factory.CreateMqttClient()

    $options = [MQTTnet.Client.MqttClientOptionsBuilder]::new()
    $options = $options.WithTcpServer($config.Broker, $config.Port)
    $options = $options.WithCredentials($config.Username, $config.Password)
    $options = $options.WithClientId("enshrouded-monitor")
    $options = $options.WithCleanSession($true)
    $options = $options.WithWillTopic("$topicPrefix/status")
    $options = $options.WithWillPayload("offline")
    $options = $options.WithWillRetain($true)
    $options = $options.Build()

    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $client.ConnectAsync($options).GetAwaiter().GetResult() | Out-Null
            Log "MQTT connecte a $($config.Broker):$($config.Port)"
            return $client
        } catch {
            Log "ERREUR connexion MQTT (tentative $i/$maxRetries) : $_"
            if ($i -lt $maxRetries) { Start-Sleep -Seconds 10 }
        }
    }
    throw "Impossible de se connecter au broker MQTT apres $maxRetries tentatives"
}

# --- Publication MQTT ---
function Publish-Mqtt($client, $topic, $payload, $retain) {
    $msg = [MQTTnet.MqttApplicationMessageBuilder]::new()
    $msg = $msg.WithTopic($topic)
    $msg = $msg.WithPayload([string]$payload)
    $msg = $msg.WithRetainFlag($retain)
    $msg = $msg.Build()
    $client.PublishAsync($msg).GetAwaiter().GetResult() | Out-Null
}

# --- Publication Discovery HA ---
function Publish-Discovery($client) {
    $config = Get-MqttConfig
    $prefix = $config.DiscoveryPrefix

    $device = @{
        identifiers  = @("enshrouded_server")
        name         = "Enshrouded Server"
        manufacturer = "Keen Games"
        model        = "Dedicated Server"
    }

    $sensors = @(
        @{ id = "players_online";     name = "Players Online";     icon = "mdi:account-group";   unit = "players" }
        @{ id = "player_list";        name = "Player List";        icon = "mdi:account-multiple" }
        @{ id = "server_status";      name = "Server Status";      icon = "mdi:server" }
        @{ id = "tick_avg";           name = "Tick Avg";           icon = "mdi:timer";           unit = "ms" }
        @{ id = "tick_max";           name = "Tick Max";           icon = "mdi:timer-alert";     unit = "ms" }
        @{ id = "entity_count";       name = "Entity Count";       icon = "mdi:cube-outline" }
        @{ id = "last_save_duration"; name = "Last Save Duration"; icon = "mdi:content-save";    unit = "ms" }
        @{ id = "base_count";         name = "Base Count";         icon = "mdi:home-group" }
        @{ id = "memory_usage";       name = "Memory Usage";       icon = "mdi:memory";          unit = "%" }
        @{ id = "error_count";        name = "Error Count";        icon = "mdi:alert-circle" }
        @{ id = "teleport_count";     name = "Teleport Count";     icon = "mdi:map-marker-path" }
        @{ id = "last_teleport";      name = "Last Teleport";      icon = "mdi:map-marker-radius" }
        @{ id = "player_network";      name = "Player Network";      icon = "mdi:lan" }
        @{ id = "uptime";             name = "Uptime";             icon = "mdi:clock-outline" }
    )

    foreach ($sensor in $sensors) {
        $discoveryPayload = @{
            name               = $sensor.name
            unique_id          = "enshrouded_$($sensor.id)"
            state_topic        = "$topicPrefix/$($sensor.id)"
            device             = $device
            availability_topic = "$topicPrefix/status"
            payload_available     = "online"
            payload_not_available = "offline"
            icon               = $sensor.icon
        }
        if ($sensor.unit) {
            $discoveryPayload.unit_of_measurement = $sensor.unit
        }

        $topic = "$prefix/sensor/enshrouded_$($sensor.id)/config"
        $json = $discoveryPayload | ConvertTo-Json -Depth 5 -Compress
        Publish-Mqtt $client $topic $json $true
    }

    Log "Discovery HA publie pour $($sensors.Count) sensors"
}

# --- Discovery dynamique pour un joueur (teleportation tracker) ---
function Publish-PlayerDiscovery($client, $playerName) {
    $config = Get-MqttConfig
    $prefix = $config.DiscoveryPrefix
    $safeName = $playerName -replace '[^a-zA-Z0-9_]', '_'

    $device = @{
        identifiers  = @("enshrouded_server")
        name         = "Enshrouded Server"
        manufacturer = "Keen Games"
        model        = "Dedicated Server"
    }

    $discoveryPayload = @{
        name               = "Teleport $playerName"
        unique_id          = "enshrouded_teleport_$safeName"
        state_topic        = "$topicPrefix/teleport/$safeName"
        json_attributes_topic = "$topicPrefix/teleport/$safeName"
        device             = $device
        availability_topic = "$topicPrefix/status"
        payload_available     = "online"
        payload_not_available = "offline"
        icon               = "mdi:map-marker-account"
    }

    $topic = "$prefix/sensor/enshrouded_teleport_$safeName/config"
    $json = $discoveryPayload | ConvertTo-Json -Depth 5 -Compress
    Publish-Mqtt $client $topic $json $true
    Log "Discovery teleport publie pour $playerName"
}

# --- Etat interne ---
$state = @{
    Players       = [System.Collections.Generic.HashSet[string]]::new()
    ServerStatus  = "offline"
    TickAvg       = 0
    TickMax       = 0
    EntityCount   = 0
    SaveDuration  = 0
    BaseCount     = 0
    MemoryUsage   = 0.0
    ErrorCount    = 0
    TeleportCount       = 0
    LastTeleport        = ""
    MachineToPlayer     = @{}        # machine index -> player name
    PlayerIdToPlayer    = @{}        # player entity id -> player name
    PendingMachineQueue = [System.Collections.Queue]::new()      # [machine, playerId] waiting for name
    MachineStats        = @{}        # machine index -> @{ ping; lost; state }
    DiscoveredPlayers   = [System.Collections.Generic.HashSet[string]]::new()  # players with discovery published
    LastTimestamp        = ""
    FileOffset          = [long]0
    LastFileSize         = [long]0
}

# --- Parseur de lignes de log ---
function Parse-LogLine($line, $state, $client) {
    # Format: [LEVEL TIMESTAMP] [tag] message
    # ou format sans tag: [LEVEL TIMESTAMP] message
    if ($line -match '^\[([EWI])\s+([\d:,]+)\]\s+(.+)$') {
        $level = $Matches[1]
        $state.LastTimestamp = $Matches[2]
        $rest = $Matches[3]

        # Compter les erreurs
        if ($level -eq 'E') {
            $state.ErrorCount++
        }

        # Extraire le tag si present
        $tag = ""
        $message = $rest
        if ($rest -match '^\[([^\]]+)\]\s+(.+)$') {
            $tag = $Matches[1]
            $message = $Matches[2]
        }

        # --- Liaison Machine -> Joueur ---
        # "Machine '1': Player '0(0)' logged in" -> file d'attente FIFO
        # Player handle '0(0)' -> entity id = 0
        if ($tag -eq "server" -and $message -match "^Machine '(\d+)': Player '(\d+)\(\d+\)' logged in") {
            $pending = @{ Machine = $Matches[1]; PlayerId = $Matches[2] }
            $state.PendingMachineQueue.Enqueue($pending)
            return $false
        }

        # "Player 'SaumonAgile' logged in with Permissions:" -> lier au premier en attente
        if ($tag -eq "server" -and $message -match "^Player '([^']+)' logged in") {
            $playerName = $Matches[1]
            $state.Players.Add($playerName) | Out-Null
            $state.ServerStatus = "online"
            if ($state.PendingMachineQueue.Count -gt 0) {
                $pending = $state.PendingMachineQueue.Dequeue()
                $state.MachineToPlayer[$pending.Machine] = $playerName
                $state.PlayerIdToPlayer[$pending.PlayerId] = $playerName
            }
            # Publier discovery teleport pour ce joueur (une seule fois)
            if ($null -ne $client -and $state.DiscoveredPlayers.Add($playerName)) {
                Publish-PlayerDiscovery $client $playerName
            }
            Log "Joueur connecte : $playerName (total: $($state.Players.Count))"
            return $true
        }

        # --- Deconnexion joueur ---
        if ($tag -eq "server" -and $message -match "^Remove Player '([^']+)'") {
            $playerName = $Matches[1]
            $state.Players.Remove($playerName) | Out-Null
            # Nettoyer les mappings machine et playerId -> joueur
            $machineToRemove = $state.MachineToPlayer.GetEnumerator() |
                Where-Object { $_.Value -eq $playerName } |
                Select-Object -First 1 -ExpandProperty Key
            if ($null -ne $machineToRemove) {
                $state.MachineToPlayer.Remove($machineToRemove)
                $state.MachineStats.Remove($machineToRemove)
            }
            $pidToRemove = $state.PlayerIdToPlayer.GetEnumerator() |
                Where-Object { $_.Value -eq $playerName } |
                Select-Object -First 1 -ExpandProperty Key
            if ($null -ne $pidToRemove) {
                $state.PlayerIdToPlayer.Remove($pidToRemove)
            }
            Log "Joueur deconnecte : $playerName (total: $($state.Players.Count))"
            return $true
        }

        # --- Session telemetry (m#N) ---
        # "  m#1(129): up 256 (270), down 23 (25), remote 255 (269), limit 1081, lost 11, ping 31 ms, OperatingNormally"
        if ($tag -eq "" -and $message -match '^\s*m#(\d+)\(\d+\):.*lost (\d+),\s*ping (\d+) ms,\s*(\S+)') {
            $machIdx = $Matches[1]
            $lost = [int]$Matches[2]
            $ping = [int]$Matches[3]
            $netState = $Matches[4]
            # Ignorer la machine locale (m#0)
            if ($machIdx -ne "0") {
                $state.MachineStats[$machIdx] = @{
                    ping  = $ping
                    lost  = $lost
                    state = $netState
                }
            }
            return $false
        }

        # --- Performance ECSS ---
        if ($tag -eq "ecss" -and $message -match 'Stats:.*Avg:([\d.]+)ms.*Max:(\d+)ms.*Ent:([\d,]+)') {
            $state.TickAvg = [double]$Matches[1]
            $state.TickMax = [int]$Matches[2]
            $state.EntityCount = [int]($Matches[3] -replace ',', '')
            return $false
        }

        # --- Sauvegarde ---
        if ($tag -eq "server" -and $message -eq "Start Saving") {
            $state.ServerStatus = "saving"
            return $false
        }

        if ($tag -eq "server" -and $message -eq "Saved") {
            $state.ServerStatus = "online"
            return $false
        }

        if ($tag -eq "server" -and $message -match 'Save Serialization took ([\d.]+) ms') {
            $state.SaveDuration = [int][double]$Matches[1]
            return $false
        }

        if ($tag -match '^save' -and $message -match 'SAVE (\d+) bases ([\d,]+) entities') {
            $state.BaseCount = [int]$Matches[1]
            return $false
        }

        # --- Grid Allocator (memoire) ---
        if ($tag -eq "Server" -and $message -match 'Grid Allocator \(\s*([\d,]+)\s*/\s*([\d,]+)\s*\)\s*([\d.]+)') {
            $state.MemoryUsage = [Math]::Round([double]$Matches[3], 2)
            return $false
        }

        # --- Bad Performance ---
        if ($tag -eq "server" -and $message -match '^Bad Performance') {
            $state.ErrorCount++
            return $false
        }

        # --- Teleportation joueur (pas de tag) ---
        if ($tag -eq "" -and $message -match 'Player EntityId (\d+) teleported From \(([\d.-]+),\s*([\d.-]+),\s*([\d.-]+)\) to \(([\d.-]+),\s*([\d.-]+),\s*([\d.-]+)\)') {
            $entityId = $Matches[1]
            $state.TeleportCount++
            $fromX = [Math]::Round([double]$Matches[2], 0)
            $fromY = [Math]::Round([double]$Matches[3], 0)
            $fromZ = [Math]::Round([double]$Matches[4], 0)
            $toX = [Math]::Round([double]$Matches[5], 0)
            $toY = [Math]::Round([double]$Matches[6], 0)
            $toZ = [Math]::Round([double]$Matches[7], 0)
            # EntityId correspond au machine index, pas au player handle
            $who = if ($state.MachineToPlayer.ContainsKey($entityId)) {
                $state.MachineToPlayer[$entityId]
            } elseif ($state.PlayerIdToPlayer.ContainsKey($entityId)) {
                $state.PlayerIdToPlayer[$entityId]
            } else { "Player#$entityId" }
            $state.LastTeleport = "$who ($fromX, $fromY, $fromZ) -> ($toX, $toY, $toZ)"

            # Publier l'evenement sur le topic du joueur pour historique HA
            if ($null -ne $client) {
                $safeName = $who -replace '[^a-zA-Z0-9_]', '_'
                $teleportData = @{
                    player = $who
                    from   = @{ x = $fromX; y = $fromY; z = $fromZ }
                    to     = @{ x = $toX; y = $toY; z = $toZ }
                    time   = $state.LastTimestamp
                } | ConvertTo-Json -Depth 3 -Compress
                Publish-Mqtt $client "$topicPrefix/teleport/$safeName" $teleportData $false
            }
            return $false
        }

        # --- Demarrage serveur ---
        if ($tag -eq "online" -and $message -match 'Server connected to Steam successfully') {
            $state.ServerStatus = "online"
            $state.ErrorCount = 0
            $state.TeleportCount = 0
            $state.LastTeleport = ""
            $state.Players.Clear()
            $state.MachineToPlayer = @{}
            $state.PlayerIdToPlayer = @{}
            $state.MachineStats = @{}
            $state.PendingMachineQueue.Clear()
            Log "Serveur Enshrouded demarre"
            return $true
        }

        # --- Arret serveur ---
        if ($tag -eq "app" -and $message -match 'Trigger gameflow shutdown') {
            $state.ServerStatus = "offline"
            $state.Players.Clear()
            $state.MachineToPlayer = @{}
            $state.PlayerIdToPlayer = @{}
            $state.MachineStats = @{}
            $state.PendingMachineQueue.Clear()
            Log "Serveur Enshrouded arrete"
            return $true
        }
    }

    return $false
}

# --- Lecture du fichier de log avec detection de rotation ---
function Read-NewLogLines($state) {
    if (-not (Test-Path $logPath)) {
        return @()
    }

    $fileInfo = Get-Item $logPath
    $currentSize = $fileInfo.Length

    # Detection de rotation (le fichier a ete remplace)
    if ($currentSize -lt $state.FileOffset) {
        Log "Rotation de log detectee, reinitialisation"
        $state.FileOffset = [long]0
        $state.ErrorCount = 0
        $state.Players.Clear()
        $state.ServerStatus = "online"
    }

    if ($currentSize -eq $state.FileOffset) {
        return @()
    }

    $lines = @()
    try {
        $stream = [System.IO.FileStream]::new(
            $logPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $stream.Seek($state.FileOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -gt 0) {
                $lines += $line
            }
        }

        $state.FileOffset = $stream.Position
        $state.LastFileSize = $currentSize

        $reader.Dispose()
        $stream.Dispose()
    } catch {
        Log "ERREUR lecture log : $_"
    }

    return $lines
}

# --- Publication de l'etat sur MQTT ---
function Publish-State($client, $state) {
    # Calculer l'uptime depuis le timestamp du log
    $uptime = "00:00:00"
    if ($state.LastTimestamp -match '^(\d+):(\d+):(\d+)') {
        $uptime = "$($Matches[1]):$($Matches[2]):$($Matches[3])"
    }

    Publish-Mqtt $client "$topicPrefix/players_online"     $state.Players.Count     $true
    Publish-Mqtt $client "$topicPrefix/player_list"         ($state.Players -join ", ") $true
    Publish-Mqtt $client "$topicPrefix/server_status"       $state.ServerStatus      $true
    Publish-Mqtt $client "$topicPrefix/tick_avg"            $state.TickAvg           $true
    Publish-Mqtt $client "$topicPrefix/tick_max"            $state.TickMax           $true
    Publish-Mqtt $client "$topicPrefix/entity_count"        $state.EntityCount       $true
    Publish-Mqtt $client "$topicPrefix/last_save_duration"  $state.SaveDuration      $true
    Publish-Mqtt $client "$topicPrefix/base_count"          $state.BaseCount         $true
    Publish-Mqtt $client "$topicPrefix/memory_usage"        $state.MemoryUsage       $true
    Publish-Mqtt $client "$topicPrefix/error_count"         $state.ErrorCount        $true
    Publish-Mqtt $client "$topicPrefix/teleport_count"      $state.TeleportCount     $true
    Publish-Mqtt $client "$topicPrefix/last_teleport"       $state.LastTeleport      $true

    # Construire le JSON player_network avec stats par joueur
    $playerNetworkData = @{}
    foreach ($machIdx in $state.MachineToPlayer.Keys) {
        $playerName = $state.MachineToPlayer[$machIdx]
        if ($state.MachineStats.ContainsKey($machIdx)) {
            $stats = $state.MachineStats[$machIdx]
            $playerNetworkData[$playerName] = @{
                ping  = $stats.ping
                lost  = $stats.lost
                state = $stats.state
            }
        }
    }
    $networkJson = if ($playerNetworkData.Count -gt 0) {
        $playerNetworkData | ConvertTo-Json -Depth 3 -Compress
    } else { "{}" }
    Publish-Mqtt $client "$topicPrefix/player_network"      $networkJson             $true

    Publish-Mqtt $client "$topicPrefix/uptime"              $uptime                  $true
}

# =============================================================================
# Point d'entree
# =============================================================================

Log "=== Demarrage du moniteur Enshrouded ==="

# --- Initialisation avec retry infini ---
# Si MQTTnet ou le broker ne sont pas disponibles, on attend plutot que crasher.
# Cela evite que NSSM redemarre le script en boucle.

$client = $null

while ($true) {
    # Phase 1 : Charger MQTTnet (attendre que la DLL soit presente)
    while ($true) {
        try {
            Load-MqttNet
            break
        } catch {
            Log "ERREUR chargement MQTTnet : $_ - nouvelle tentative dans 30s"
            Start-Sleep -Seconds 30
        }
    }

    # Phase 2 : Connexion MQTT (attendre que le broker soit disponible)
    while ($null -eq $client -or -not $client.IsConnected) {
        try {
            $client = Connect-Mqtt
            Publish-Discovery $client
            Publish-Mqtt $client "$topicPrefix/status" "online" $true
            Log "Surveillance de : $logPath"
            Log "Publication MQTT toutes les ${pollInterval}s"
        } catch {
            Log "ERREUR connexion MQTT : $_ - nouvelle tentative dans 30s"
            $client = $null
            Start-Sleep -Seconds 30
        }
    }

    # Phase 3 : Boucle principale
    try {
        while ($true) {
            # Verifier la connexion MQTT
            if (-not $client.IsConnected) {
                Log "MQTT deconnecte, reconnexion..."
                break
            }

            # Lire et parser les nouvelles lignes
            $newLines = Read-NewLogLines $state

            foreach ($line in $newLines) {
                Parse-LogLine $line $state $client | Out-Null
            }

            # Publier l'etat courant
            Publish-State $client $state

            Start-Sleep -Seconds $pollInterval
        }
    } catch {
        Log "ERREUR boucle principale : $_ - redemarrage dans 10s"
        Start-Sleep -Seconds 10
    }

    # Reset client pour forcer reconnexion
    try { $client.DisconnectAsync().GetAwaiter().GetResult() | Out-Null } catch {}
    $client = $null
}
