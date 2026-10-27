#!/bin/zsh
# ORCHESTRATOR CHAOS — server tạm AUTH ON + 5 hacker song song + tải người dùng 50/100/200/500.
set -u
cd "$(dirname "$0")/../.."
PY="$(pwd)/.venv-mac312/bin/python"
TMP=$(mktemp -d /tmp/hue_chaos_XXXX)
LOG=/tmp/hue_logs/chaos
mkdir -p "$LOG"
pkill -f "port 8010" 2>/dev/null || true
sleep 1

export DATABASE_URL="sqlite:///$TMP/db.sqlite"
export STORAGE_DIR="$TMP/storage"
export MODELS_DIR="$TMP/models"
export AUTH_REQUIRED=true
export SECRET_KEY=$($PY -c "import secrets;print(secrets.token_hex(32))")
export HUE_SECURITY_LOG="$TMP/sec.log"
export CHAOS_BASE="http://127.0.0.1:8010"

echo "══ CHAOS TEST — server tạm :8010 (AUTH ON, DB tạm) ══"
(cd server && nohup $PY -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --no-proxy-headers > "$LOG/server.log" 2>&1 & echo $! > "$TMP/server.pid")
sleep 4
SERVER_PID=$(cat "$TMP/server.pid")
kill -0 "$SERVER_PID" 2>/dev/null || { echo "!!! SERVER KHÔNG KHỞI ĐỘNG — abort"; tail -5 "$LOG/server.log"; exit 1; }
curl -s -m 5 http://127.0.0.1:8010/health > /dev/null || { echo "!!! health fail — abort"; exit 1; }
echo "server PID $SERVER_PID healthy"
(cd server && $PY -m app.database.seed_heritage > /dev/null 2>&1)
$PY server/tools/chaos_setup.py --db "$TMP/db.sqlite" --codes-out "$TMP/codes.txt" --codes 300

ADMIN_TOKEN=$($PY - <<'PYTOKEN'
import sys
sys.path.insert(0, 'server')
from app.api.auth import make_token
from app.database.session import SessionLocal
from app.database import crud
db = SessionLocal()
admin = crud.get_user(db, 'ghitatruongle')
print(make_token(admin.id, admin.token_epoch or 0))
db.close()
PYTOKEN
)
echo "admin token: ${#ADMIN_TOKEN} ký tự"
export CHAOS_ADMIN_TOKEN="$ADMIN_TOKEN"

$PY server/tools/chaos_lesson.py
LESSON_ID=$(cat "$TMP/lesson_id")

$PY server/tools/chaos_users.py "$TMP/codes.txt" "$TMP/tokens.txt"

ATK=(atk_privilege_escalation atk_admin_takeover atk_sqli_traversal atk_invite_race atk_upload_malware   atk6_bruteforce_distributed atk7_token_format atk8_header_injection atk9_password_race atk10_oversized   atk11_http_methods atk12_content_type atk13_unicode_abuse atk14_enumeration atk15_static_probe   atk16_param_pollution atk17_register_abuse atk18_storage_abuse atk19_task_flood atk20_auth_switching)
PRIV_CODE=$(head -1 "$TMP/codes.txt")
export ATTACK_CODE=$PRIV_CODE
for name in $ATK; do
  case $name in
    atk_privilege_escalation) ARGS="--code $PRIV_CODE --rounds 20";;
    atk_invite_race) ARGS="--codes-file $TMP/codes.txt --rounds 40";;
    atk_admin_takeover) ARGS="--rounds 8";;
    atk6_bruteforce_distributed) ARGS="--target ghitatruongle --rounds 30";;
    *) ARGS="--rounds 12";;
  esac
  nohup $PY server/tools/attack/$name.py --base http://127.0.0.1:8010 $ARGS > "$LOG/$name.log" 2>&1 &
done
sleep 2
echo "20 hacker đã triển khai — bắt đầu các tầng tải..."

for TIER in 50 100 200 500; do
  echo "══ TẦNG $TIER TRUY CẬP ĐỒNG THỜI (+ 5 hacker) ══"
  $PY server/tools/load_users.py --base http://127.0.0.1:8010 --tier $TIER --seconds 15 \
    --lesson-id "$LESSON_ID" --tokens-file "$TMP/tokens.txt" --out "$TMP/load_$TIER.json"
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "!!! SERVER CHẾT ở tầng $TIER"; tail -10 "$LOG/server.log"; exit 1; }
  echo "  health: $(curl -s -m 5 http://127.0.0.1:8010/health | head -c 60)"
  echo -n "  admin/users: "
  $PY server/tools/chaos_admin_count.py "$ADMIN_TOKEN" || true
done

echo "══ Chờ hackers kết thúc ══"
for i in {1..300}; do
  N=$(pgrep -fc "tools/attack/atk_" 2>/dev/null || echo 0)
  [ "$N" = "0" ] && break
  sleep 1
done

echo "══ VERDICT ══"
COMPROMISED=0
for name in $ATK; do
  V=$(grep "VERDICT" "$LOG/$name.log" 2>/dev/null || echo "VERDICT $name: KHÔNG KẾT THÚC")
  echo "$V"
  echo "$V" | grep -q "COMPROMISED" && COMPROMISED=1
done

echo "══ TẢI THEO TẦNG ══"
for TIER in 50 100 200 500; do
  [ -f "$TMP/load_$TIER.json" ] && $PY -c "
import json
d = json.load(open('$TMP/load_$TIER.json'))
print(f\"{d['tier']:>4} truy cập: req={d['requests']} 5xx={d['5xx']} 429={d['429']} p50={d['p50_ms']}ms p95={d['p95_ms']}ms max={d['max_ms']}ms\")"
done

echo "══ ADMIN CUỐI ══"
$PY server/tools/chaos_admin_count.py "$ADMIN_TOKEN"

kill "$SERVER_PID" 2>/dev/null || true
if [ "$COMPROMISED" = "1" ]; then
  echo "══ VERDICT CHAOS: CÓ LỖ HỔNG BỊ KHAI THÁC ══"
  exit 1
else
  echo "══ VERDICT CHAOS: SẠCH — KHÔNG LỖ HỔNG NÀO BỊ KHAI THÁC ══"
fi
