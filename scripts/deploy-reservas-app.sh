#!/usr/bin/env bash
# Despliega stack mínimo: app-api, app-core, db-postgres, monitoring
set -euo pipefail
LAB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=load-secrets.sh
source "$(dirname "$0")/load-secrets.sh"
APP_DIR="${LAB_ROOT}/app"
: "${DB_PASS:?Defina DB_PASS en secrets/lab.secrets.env}"
: "${HOST_SUDO_PASS:?Defina HOST_SUDO_PASS en secrets/lab.secrets.env}"
export SUDO_PASS="${SUDO_PASS:-$HOST_SUDO_PASS}"
REQUIRED_NODES=(app-api app-core db-postgres monitoring)
LAB_TARGETS=(app-api app-core db-postgres monitoring)

log() { echo "[reservas] $*"; }
die() { echo "[reservas] ERROR: $*" >&2; exit 1; }

ensure_incus() {
  systemctl is-active --quiet incus || die "Incus no está activo. Ejecuta: sudo systemctl start incus"
}

ensure_nodes() {
  local missing=()
  for n in "${REQUIRED_NODES[@]}"; do
    incus info "$n" &>/dev/null || missing+=("$n")
  done
  if ((${#missing[@]})); then
    die "Faltan contenedores: ${missing[*]}. Ejecuta: cd ~/incus-lab && ./lab-deploy.sh apply"
  fi
  for n in "${REQUIRED_NODES[@]}"; do
    if [[ "$(incus list "$n" -c s --format csv)" != *RUNNING* ]]; then
      log "Arrancando $n..."
      incus start "$n"
    fi
  done
}

ufw_lab_routes() {
  echo "$SUDO_PASS" | sudo -S ufw route allow in on lab-br0 out on enp2s0 2>/dev/null || true
  echo "$SUDO_PASS" | sudo -S ufw route allow in on enp2s0 out on lab-br0 2>/dev/null || true
  echo "$SUDO_PASS" | sudo -S ip link set lab-br0 up 2>/dev/null || true
}

install_node_exporter() {
  local node="$1"
  incus exec "$node" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v prometheus-node-exporter &>/dev/null; then
      apt-get update -qq
      apt-get install -y -qq prometheus-node-exporter
    fi
    systemctl enable --now prometheus-node-exporter
  " 2>/dev/null || log "node_exporter omitido en $node (opcional)"
}

configure_postgres_remote() {
  incus exec db-postgres -- bash -c "
    PGVER=\$(ls /etc/postgresql/)
    CONF=/etc/postgresql/\$PGVER/main/postgresql.conf
    HBA=/etc/postgresql/\$PGVER/main/pg_hba.conf
    sed -i \"s/^#*listen_addresses.*/listen_addresses = '*'/\" \"\$CONF\"
    grep -q \"10.10.0.0/24\" \"\$HBA\" || echo \"host all all 10.10.0.0/24 scram-sha-256\" >> \"\$HBA\"
    systemctl restart postgresql
  "
}

deploy_db() {
  log "PostgreSQL en db-postgres"
  incus exec db-postgres -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq postgresql postgresql-contrib
    systemctl enable --now postgresql
  "
  incus exec db-postgres -- sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='lab'" | grep -q 1 || \
    incus exec db-postgres -- sudo -u postgres psql -c "CREATE USER lab WITH PASSWORD '${DB_PASS}';"
  incus exec db-postgres -- sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='reservas'" | grep -q 1 || \
    incus exec db-postgres -- sudo -u postgres psql -c "CREATE DATABASE reservas OWNER lab;"
  incus exec db-postgres -- sudo -u postgres psql -d reservas -c "GRANT ALL ON SCHEMA public TO lab;"
  incus exec db-postgres -- bash -c 'cat > /var/tmp/schema.sql' < "${APP_DIR}/schema.sql"
  incus exec db-postgres -- sudo -u postgres psql -d reservas -f /var/tmp/schema.sql
  incus exec db-postgres -- sudo -u postgres psql -d reservas -c "
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lab;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lab;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO lab;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lab;
    UPDATE users SET password_hash='plain:lab123' WHERE email='admin@lab.edu';
  "
  configure_postgres_remote
  install_node_exporter db-postgres
}

deploy_api() {
  log "API en app-api"
  incus exec app-api -- mkdir -p /opt/lab/reservas
  incus file push "${APP_DIR}/requirements.txt" app-api/opt/lab/reservas/requirements.txt
  incus file push "${APP_DIR}/main.py" app-api/opt/lab/reservas/main.py
  incus exec app-api -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq python3-venv python3-pip curl
    test -d /opt/lab/venv || python3 -m venv /opt/lab/venv
    /opt/lab/venv/bin/pip install -q -r /opt/lab/reservas/requirements.txt
  "
  incus exec app-api -- bash -c 'cat > /etc/systemd/system/reservas-api.service <<EOF
[Unit]
Description=Reservas Lab API
After=network.target postgresql.service

[Service]
Environment=DB_HOST=10.10.0.40 DB_NAME=reservas DB_USER=lab DB_PASS='"${DB_PASS}"'
WorkingDirectory=/opt/lab/reservas
ExecStart=/opt/lab/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now reservas-api'
  install_node_exporter app-api
}

deploy_core() {
  log "Core en app-core"
  incus exec app-core -- mkdir -p /opt/lab/reservas
  incus exec app-core -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq python3-venv python3-pip curl
    test -d /opt/lab/venv || python3 -m venv /opt/lab/venv
    /opt/lab/venv/bin/pip install -q fastapi uvicorn httpx
  "
  incus file push "${APP_DIR}/core_main.py" app-core/opt/lab/reservas/core_main.py
  incus exec app-core -- bash -c 'cat > /etc/systemd/system/reservas-core.service <<EOF
[Unit]
Description=Reservas Lab Core
After=network.target

[Service]
Environment=API_URL=http://10.10.0.20:8080
WorkingDirectory=/opt/lab/reservas
ExecStart=/opt/lab/venv/bin/uvicorn core_main:app --host 0.0.0.0 --port 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now reservas-core'
  install_node_exporter app-core
}

deploy_monitoring() {
  log "Prometheus + Grafana en monitoring"
  incus exec monitoring -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq prometheus prometheus-node-exporter curl gpg
    if ! command -v grafana-server &>/dev/null; then
      curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana.gpg
      echo \"deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main\" > /etc/apt/sources.list.d/grafana.list
      apt-get update -qq
      apt-get install -y -qq grafana
    fi
    systemctl enable --now prometheus-node-exporter grafana-server
  "
  local targets=""
  for n in "${LAB_TARGETS[@]}"; do
    ip=$(incus list "$n" -c 4 --format csv | cut -d, -f1 | awk '{print $1}' | head -1)
    targets="${targets}        - ${ip}:9100\n"
  done
  incus exec monitoring -- bash -c "cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: node
    static_configs:
      - targets:
$(echo -e "${targets}")
  - job_name: reservas
    metrics_path: /metrics
    static_configs:
      - targets:
        - 10.10.0.20:8080
        - 10.10.0.30:8080
EOF
systemctl restart prometheus"
  incus exec monitoring -- bash -c 'mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/lab.yaml <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
EOF
systemctl restart grafana-server'
}

validate_app() {
  log "Validación del stack mínimo"
  sleep 2
  curl -sf http://10.10.0.20:8080/health | python3 -m json.tool
  curl -sf http://10.10.0.30:8080/health | python3 -m json.tool
  TOKEN=$(curl -sf -X POST http://10.10.0.20:8080/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"admin@lab.edu","password":"lab123"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[\"access_token\"])")
  curl -sf -H "Authorization: Bearer $TOKEN" http://10.10.0.20:8080/resources \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get("items",[])), "recursos")"
  curl -sf http://10.10.0.50:9090/-/ready && echo "Prometheus: OK"
  curl -sf -o /dev/null -w "Grafana HTTP %{http_code}\n" http://10.10.0.50:3000/login
  log "=== Stack listo ==="
  log "API Swagger:  http://10.10.0.20:8080/docs"
  log "Core health:  http://10.10.0.30:8080/health"
  log "Prometheus:   http://10.10.0.50:9090"
  log "Grafana:      http://10.10.0.50:3000  (admin / admin)"
  log "Login app:    admin@lab.edu / lab123"
}

main() {
  ensure_incus
  ensure_nodes
  ufw_lab_routes
  deploy_db
  deploy_api
  deploy_core
  deploy_monitoring
  validate_app
  log "Despliegue completado."
}

main "$@"
