# Canopy OS · instala la copia automática de respaldos en esta computadora Windows.
# Ejecutar UNA vez en PowerShell (no hace falta administrador):
#   powershell -ExecutionPolicy Bypass -File .\instalar-windows.ps1
# Crea una tarea "Respaldos del café" que corre al iniciar sesión y cada hora; si la computadora estuvo
# apagada a la hora programada, corre apenas pueda ("Run task as soon as possible after a scheduled start is missed").
$script = Join-Path $PSScriptRoot 'sincronizar-respaldos.ps1'
$dest = Join-Path $env:USERPROFILE 'Documents\HangingGarden-Respaldos\programa'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item $script $dest -Force
$target = Join-Path $dest 'sincronizar-respaldos.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$target`""
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$hourly = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 1)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'Respaldos del café' -Action $action -Trigger @($atLogon, $hourly) -Settings $settings -Force | Out-Null
Write-Output "Listo. La tarea 'Respaldos del café' quedó instalada. Primera copia ahora…"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target
Write-Output "Revise $(Join-Path $env:USERPROFILE 'Documents\HangingGarden-Respaldos\ESTADO.txt')"
