@echo off
echo ======================================================================
echo Reparando permisos de clave privada SSH (id_ed25519) en Windows...
echo ======================================================================
cd /d "%~dp0"
icacls.exe id_ed25519 /inheritance:r >nul 2>&1
icacls.exe id_ed25519 /grant:r "%USERNAME%:R" >nul 2>&1
echo [OK] Permisos corregidos exitosamente. Ahora podes conectar por SSH:
echo      ssh -i id_ed25519 -o StrictHostKeyChecking=no ubuntu@...
