# Script de reparacion de permisos para clave privada SSH en Windows
$keyPath = Join-Path $PSScriptRoot "id_ed25519"
if (Test-Path $keyPath) {
    Write-Host "Restringiendo permisos NTFS en $keyPath..." -ForegroundColor Cyan
    cmd.exe /c "icacls `"$keyPath`" /inheritance:r /grant:r `"$($env:USERNAME):R`""
    Write-Host "[OK] Clave privada protegida. Ya podes conectarte sin advertencias." -ForegroundColor Green
} else {
    Write-Host "[!] No se encontro el archivo id_ed25519 en este directorio." -ForegroundColor Yellow
}
