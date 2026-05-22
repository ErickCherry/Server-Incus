#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=load-secrets.sh
source "$SCRIPT_DIR/load-secrets.sh"
: "${APP_ADMIN_EMAIL:?}" "${APP_ADMIN_PASS:?}"
echo "[smoke] health API"; curl -sf http://10.10.0.20:8080/health
echo ""; echo "[smoke] health Core"; curl -sf http://10.10.0.30:8080/health
echo ""; echo "[smoke] login"
TOKEN=$(curl -sf -X POST http://10.10.0.20:8080/auth/login -H "Content-Type: application/json" \
  -d "{\"email\":\"${APP_ADMIN_EMAIL}\",\"password\":\"${APP_ADMIN_PASS}\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
curl -sf -H "Authorization: Bearer $TOKEN" http://10.10.0.20:8080/resources | python3 -c "import sys,json; print('recursos:', len(json.load(sys.stdin)['items']))"
curl -sf http://10.10.0.50:9090/-/ready && echo "prometheus ok"
curl -sf -o /dev/null -w "grafana:%{http_code}\n" http://10.10.0.50:3000/login
echo "[smoke] OK"
