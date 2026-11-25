#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${1:-$REPO_DIR/hue_heritage.db}"
OUT_DIR="${2:-$REPO_DIR/backups}"
KEEP="${3:-7}"

if ! [[ "$KEEP" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid keep count: $KEEP" >&2
  exit 1
fi

if [ ! -f "$DB" ]; then
  echo "db not found: $DB" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET="$OUT_DIR/hue_heritage_${STAMP}.db"
ESCAPED_TARGET="${TARGET//\'/\'\'}"

sqlite3 "$DB" ".backup '$ESCAPED_TARGET'"
RESULT="$(sqlite3 "$TARGET" 'PRAGMA quick_check;')"
RESULT="${RESULT%%$'\n'*}"
if [ "$RESULT" != "ok" ]; then
  rm -f -- "$TARGET"
  echo "backup failed integrity check: $RESULT" >&2
  exit 1
fi

while IFS= read -r old; do
  [ -n "$old" ] && rm -f -- "$old"
done < <(ls -1t "$OUT_DIR"/hue_heritage_*.db 2>/dev/null | tail -n +"$((KEEP + 1))")
COUNT="$(ls -1t "$OUT_DIR"/hue_heritage_*.db 2>/dev/null | wc -l | tr -d ' ')"

echo "backup ok: $TARGET ($COUNT kept, keep=$KEEP)"
