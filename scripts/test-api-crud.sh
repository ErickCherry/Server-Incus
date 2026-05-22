#!/usr/bin/env bash
# Prueba E2E: auth, CRUD recursos, CRUD reservas, eventos
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=load-secrets.sh
source "$SCRIPT_DIR/load-secrets.sh"
: "${APP_ADMIN_EMAIL:?}" "${APP_ADMIN_PASS:?}"
API="${API_URL:-http://10.10.0.20:8080}"

json() { python3 -c "import sys,json; print(json.load(sys.stdin)['$1'])"; }

echo "=== 1. Login ==="
LOGIN=$(curl -sf -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"${APP_ADMIN_EMAIL}\",\"password\":\"${APP_ADMIN_PASS}\"}")
TOKEN=$(echo "$LOGIN" | json access_token)
echo "user: $(echo "$LOGIN" | json email)"

AUTH="Authorization: Bearer $TOKEN"

echo "=== 2. CRUD recursos ==="
RID=$(curl -sf -X POST "$API/resources" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name":"Lab Test CRUD","resource_type":"laboratorio","capacity":10,"description":"prueba"}' | json id)
echo "creado recurso id=$RID"
curl -sf -H "$AUTH" "$API/resources/$RID" | python3 -m json.tool | head -5
curl -sf -X PUT "$API/resources/$RID" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"capacity":12}' | json capacity

echo "=== 3. CRUD reservas ==="
RES=$(curl -sf -X POST "$API/reservations" -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"resource_id\":$RID,\"starts_at\":\"2026-07-01T09:00:00\",\"ends_at\":\"2026-07-01T11:00:00\",\"notes\":\"test crud\"}")
RESID=$(echo "$RES" | json id)
echo "creada reserva id=$RESID"
curl -sf -H "$AUTH" "$API/reservations/$RESID" | json status
curl -sf -X PUT "$API/reservations/$RESID" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"notes":"actualizada"}' | json notes

echo "=== 4. Eventos ==="
curl -sf -H "$AUTH" "$API/events?limit=5" | python3 -c "import sys,json; print('eventos:', len(json.load(sys.stdin)['items']))"
curl -sf -H "$AUTH" "$API/events/errors?limit=3" | python3 -c "import sys,json; d=json.load(sys.stdin); print('errores:', len(d['items']))"

echo "=== 5. Limpieza ==="
curl -sf -X DELETE "$API/reservations/$RESID" -H "$AUTH" -o /dev/null -w "del reserva %{http_code}\n"
curl -sf -X DELETE "$API/resources/$RID" -H "$AUTH" -o /dev/null -w "del recurso %{http_code}\n"

echo "=== 6. Logout ==="
curl -sf -X POST "$API/auth/logout" -H "$AUTH" >/dev/null && echo "logout ok"

echo "=== CRUD API OK ==="
