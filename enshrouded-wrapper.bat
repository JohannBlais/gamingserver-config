@echo off
REM Wrapper pour le service Enshrouded
REM Lance le serveur, attend qu'il s'arrête, puis exécute le backup

"C:\SteamApps\EnshroudedServer\enshrouded_server.exe"

REM Le serveur s'est arrêté, lancer le backup
powershell.exe -ExecutionPolicy Bypass -File "C:\source\gamingserver-config\shutdown.ps1"
