# =====================================================================================================
# Canopy OS · copia los respaldos cifrados a esta computadora (Windows)
# Lo corre el Programador de tareas cada hora y al iniciar sesión (vea instalar-windows.ps1).
# Si la computadora estuvo apagada, trae TODOS los respaldos que faltan.
# Configuración: $env:USERPROFILE\canopy-respaldos.conf.ps1, por ejemplo:
#   $REMOTE = "offsite:canopy-respaldos"        # destino rclone de solo LECTURA  (o)
#   $SOURCE_DIR = "E:\canopy-respaldos"          # una carpeta (USB)
#   $DEST = "$env:USERPROFILE\Documents\HangingGarden-Respaldos"
# Guarda: últimos 14 días; uno por semana 8 semanas; uno por mes 24 meses; uno por año para siempre.
# =====================================================================================================
$ErrorActionPreference = 'Continue'
$REMOTE = $null; $SOURCE_DIR = $null
$DEST = Join-Path $env:USERPROFILE 'Documents\HangingGarden-Respaldos'
$LATE_HOURS = 36
$conf = Join-Path $env:USERPROFILE 'canopy-respaldos.conf.ps1'
if (Test-Path $conf) { . $conf }
$archivo = Join-Path $DEST 'archivo'; $entrada = Join-Path $DEST '.entrada'
New-Item -ItemType Directory -Force -Path $archivo, $entrada | Out-Null
$log = Join-Path $DEST 'registro.txt'
$problems = New-Object System.Collections.Generic.List[string]
function Say($m) { $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m; Add-Content -Path $log -Value $line; Write-Output $line }

# 1) traer lo nuevo (nunca sobrescribe ni borra)
if ($REMOTE) {
  & rclone copy $REMOTE $entrada --include '*.tar.age' --include '*.tar.age.sha256' --immutable --max-age 400d 2>> $log
  if ($LASTEXITCODE -ne 0) { $problems.Add('no se pudo conectar con la copia en la nube') }
} elseif ($SOURCE_DIR) {
  Get-ChildItem -Path $SOURCE_DIR -Recurse -File -Include '*.tar.age', '*.tar.age.sha256' -ErrorAction SilentlyContinue |
    ForEach-Object { $t = Join-Path $entrada $_.Name; if (-not (Test-Path $t)) { Copy-Item $_.FullName $t } }
} else { $problems.Add("falta `$REMOTE o `$SOURCE_DIR en $conf") }

# 2) verificar y archivar
Get-ChildItem -Path $entrada -File -Filter '*.tar.age' | ForEach-Object {
  $b = $_.Name; $sum = Join-Path $entrada "$b.sha256"
  if (Test-Path (Join-Path $archivo $b)) { Remove-Item $_.FullName, $sum -ErrorAction SilentlyContinue; return }
  if (-not (Test-Path $sum)) { return }
  $want = ((Get-Content $sum -Raw).Trim() -split '\s+')[0].ToLower()
  $got = (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower()
  if ($want -eq $got) { Move-Item $_.FullName (Join-Path $archivo $b); Move-Item $sum (Join-Path $archivo "$b.sha256"); Say "guardado $b" }
  else { Say "DAÑADO $b (la suma no coincide); se volverá a bajar"; Remove-Item $_.FullName, $sum; $problems.Add('un respaldo llegó dañado y se volverá a bajar') }
}

# 3) política de guardado (por la fecha del nombre canopy-respaldo-YYYYMMDD-HHMMZ.tar.age)
$now = (Get-Date).ToUniversalTime()
$files = Get-ChildItem -Path $archivo -File | Where-Object { $_.Name -match '^canopy-respaldo-(\d{8})-(\d{4})Z\.tar\.age$' } | Sort-Object Name
$items = foreach ($f in $files) {
  $null = $f.Name -match '^canopy-respaldo-(\d{8})-(\d{4})Z'
  $d = [datetime]::ParseExact($Matches[1], 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
  [pscustomobject]@{ F = $f; D = $d; Age = [int][math]::Floor(($now.Date - $d).TotalDays)
                     W = [int][math]::Floor(($d - [datetime]'1970-01-05').TotalDays / 7); M = $d.ToString('yyyyMM'); Y = $d.Year }
}
$lastW = @{}; $lastM = @{}; $lastY = @{}
foreach ($i in $items) { $lastW[$i.W] = $i.F.Name; $lastM[$i.M] = $i.F.Name; $lastY[$i.Y] = $i.F.Name }
foreach ($i in $items) {
  $keep = ($i.Age -le 14) -or ($i.Age -le 56 -and $lastW[$i.W] -eq $i.F.Name) -or ($i.Age -le 731 -and $lastM[$i.M] -eq $i.F.Name) -or ($lastY[$i.Y] -eq $i.F.Name)
  if (-not $keep) { Remove-Item $i.F.FullName, "$($i.F.FullName).sha256" -ErrorAction SilentlyContinue; Say "retirado (política de guardado) $($i.F.Name)" }
}

# 4) estado y aviso
$left = Get-ChildItem -Path $archivo -File -Filter '*.tar.age' | Sort-Object Name
$newest = $left | Select-Object -Last 1
if (-not $newest) { $problems.Add('todavía no hay ningún respaldo en esta computadora') }
else {
  $null = $newest.Name -match '^canopy-respaldo-(\d{8})-(\d{4})Z'
  $ts = [datetime]::ParseExact("$($Matches[1])$($Matches[2])", 'yyyyMMddHHmm', [Globalization.CultureInfo]::InvariantCulture)
  $hours = [int]($now - $ts).TotalHours
  if ($hours -gt $LATE_HOURS) { $problems.Add("el respaldo más nuevo tiene $hours horas") }
}
$estado = @("Respaldos del café · revisado $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
            "Respaldos guardados en esta computadora: $($left.Count)",
            "Más nuevo: $(if ($newest) { $newest.Name } else { 'ninguno' })")
if ($problems.Count -eq 0) { $estado += 'Estado: BIEN' } else { $estado += 'Estado: ATENCIÓN'; $estado += ($problems | ForEach-Object { " - $_" }) }
Set-Content -Path (Join-Path $DEST 'ESTADO.txt') -Value $estado -Encoding UTF8
if ($problems.Count -gt 0) {
  Say "ATENCIÓN: $($problems -join '; ')"
  try { (New-Object -ComObject WScript.Shell).Popup("Respaldos del café: $($problems[0])", 30, 'Respaldos del café', 48) | Out-Null } catch {}
  exit 1
}
exit 0
