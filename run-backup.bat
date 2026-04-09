@echo off
REM Hook post-arrêt du service Enshrouded (appelé par NSSM AppEvents Exit/Post)
powershell.exe -ExecutionPolicy Bypass -File "C:\source\gamingserver-config\backup.ps1"
