@echo off
setlocal
cd /d "%~dp0"
start "Invitation server" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve_invitation.ps1"
powershell.exe -NoProfile -Command "$url='http://localhost:8080/'; for ($attempt=0; $attempt -lt 20; $attempt++) { try { $response=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 1; if ($response.StatusCode -eq 200 -and $response.Content -match 'Margaux') { Start-Process $url; exit 0 } } catch {}; Start-Sleep -Milliseconds 500 }; Write-Host 'The invitation server did not become ready at http://localhost:8080/.' -ForegroundColor Red; Read-Host 'Check the Invitation server window, then press Enter'; exit 1"
