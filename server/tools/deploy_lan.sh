#!/bin/zsh
# Deploy LAN một lệnh: build web + khởi động server 0.0.0.0:8000
set -e
cd "$(dirname "$0")/../.."

echo "== 1/2 Build Flutter web =="
cd app
flutter build web --release
cd ..

echo "== 2/2 Khởi động server (0.0.0.0:8000) =="
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 1
if launchctl print gui/$(id -u)/com.ghita.hueheritagemusic.server > /dev/null 2>&1; then
  echo "launchd đang quản server — kickstart để nạp code mới"
  launchctl kickstart -k gui/$(id -u)/com.ghita.hueheritagemusic.server
  sleep 4
else
  cd server
  mkdir -p /tmp/hue_logs
  nohup ../.venv-mac312/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers --limit-concurrency 512 > /tmp/hue_logs/lan_server.log 2>&1 & disown
  sleep 4
  cd ..
fi
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
echo "== XONG =="
echo "Local:  http://127.0.0.1:8000"
echo "LAN:    http://$IP:8000"
echo "Health: $(curl -s -m 5 http://127.0.0.1:8000/health)"
