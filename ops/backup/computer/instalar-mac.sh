#!/usr/bin/env bash
# Canopy OS · instala la copia automática de respaldos en esta Mac.
# Ejecutar UNA vez en Terminal:   bash instalar-mac.sh
# Crea un agente de launchd que corre al iniciar sesión (RunAtLoad) y cada hora (StartInterval).
# Así, aunque la Mac estuviera apagada a la hora de siempre, al encenderla trae lo que falta.
set -euo pipefail
DEST_DIR="$HOME/Documents/HangingGarden-Respaldos/programa"
mkdir -p "$DEST_DIR" "$HOME/Library/LaunchAgents"
cp "$(cd "$(dirname "$0")" && pwd)/sincronizar-respaldos.sh" "$DEST_DIR/"
chmod +x "$DEST_DIR/sincronizar-respaldos.sh"
PLIST="$HOME/Library/LaunchAgents/cr.hanginggarden.respaldos.plist"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>cr.hanginggarden.respaldos</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DEST_DIR/sincronizar-respaldos.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StandardOutPath</key><string>$HOME/Documents/HangingGarden-Respaldos/launchd.log</string>
  <key>StandardErrorPath</key><string>$HOME/Documents/HangingGarden-Respaldos/launchd.log</string>
</dict></plist>
PL
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Listo. Revise ~/Documents/HangingGarden-Respaldos/ESTADO.txt en unos minutos."
