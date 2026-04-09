# gamingserver-config

Configuration et scripts de provisionnement pour le serveur dédié Enshrouded (machine Windows).

## Prérequis

- Windows 10/11 avec accès administrateur
- Wake-on-LAN activé dans le BIOS
- Connexion réseau vers le partage `\\HomeServer\Backup\Enshrouded Server`

## Installation

### 1. Initialisation (machine vierge)

Ouvrir PowerShell en administrateur et exécuter :

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/JohannBlais/gamingserver-config/main/init.ps1 | iex
```

Ce script installe Git et clone le repo dans `C:\source\gamingserver-config`.

### 2. Setup complet

```powershell
cd C:\source\gamingserver-config
.\setup.ps1
```

Ce script configure automatiquement :

1. **SteamCMD** — téléchargement et installation
2. **Enshrouded Dedicated Server** — installation dans `C:\SteamApps\EnshroudedServer`
3. **NSSM** — installation via winget
4. **Service Windows** — création du service EnshroudedServer (démarrage auto, arrêt propre 30s)
5. **Fast Startup** — désactivation via GPO (nécessaire pour le Wake-on-LAN)
6. **Identifiants réseau** — stockage des credentials du partage `\\HomeServer` (demande interactive)
7. **Backup à l'arrêt** — configuration du script de backup comme GPO d'arrêt
8. **HASS.Agent** — copie des configs sensors/commands (installation manuelle de HASS.Agent requise au préalable)
9. **Démarrage** — lancement optionnel du serveur

### 3. Configuration manuelle post-setup

- **HASS.Agent Satellite Service** : installer depuis https://hassagent.readthedocs.io/, puis remplacer les placeholders dans les fichiers de config :
  - `servicemqttsettings.json` : `<MQTT_USERNAME>`, `<MQTT_PASSWORD>`
  - `servicesettings.json` : `<HA_LONG_LIVED_TOKEN>`
- **Redémarrer la machine** pour activer le Wake-on-LAN

## Scripts

| Script | Description |
|--------|-------------|
| `init.ps1` | Bootstrap : installe Git et clone le repo |
| `setup.ps1` | Provisionnement complet de la machine |
| `backup.ps1` | Sauvegarde des saves et config vers `\\HomeServer\Backup\Enshrouded Server` |

## Structure

```
gamingserver-config/
  init.ps1                  # Bootstrap
  setup.ps1                 # Setup complet
  backup.ps1                # Backup (déclenché au shutdown)
  HASS.Agent/config/        # Configs HASS.Agent Satellite Service
    commands.json            # Commandes MQTT (start/stop/shutdown)
    sensors.json             # Sensors MQTT (CPU, RAM, service state, storage)
    servicemqttsettings.json # Config MQTT (contient des placeholders)
    servicesettings.json     # Config service (contient des placeholders)
```

## Intégration Home Assistant

La machine est pilotée depuis HA via :

- **Wake-on-LAN** (`switch.serveur_enshrouded`) — allumage à distance
- **HASS.Agent MQTT** — monitoring CPU/RAM/service state + commandes start/stop/shutdown
- **Dashboard** — onglet Enshrouded dans le dashboard Virtual Machines
