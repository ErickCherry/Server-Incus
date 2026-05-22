# Documentación completa — Laboratorio Server-Incus

Guía operativa del proyecto desplegado en **server-fintek** (`192.168.1.129`), ruta en servidor: `~/incus-lab`.

---

## 1. Resumen del proyecto

Sistema de **reservas académicas** con:

- Contenedores **Incus** en red privada `10.10.0.0/24`
- Infraestructura declarada con **OpenTofu**
- Configuración y despliegue con **Ansible**
- API **FastAPI** + **PostgreSQL**
- Observabilidad **Prometheus** + **Grafana**

---

## 2. Qué está instalado

### En el host (server-fintek)

| Componente | Uso | Comando verificación |
|------------|-----|----------------------|
| Ubuntu 24.04 | SO del servidor | `lsb_release -a` |
| Incus | Contenedores y redes | `incus version` |
| OpenTofu | IaC (snap) | `/snap/bin/tofu version` |
| Ansible | Playbooks | `ansible --version` |
| Python 3 | Scripts y app | `python3 --version` |
| ZFS | Pool `default` para volúmenes | `zfs list` |
| SSH | Acceso y bootstrap a nodos | `systemctl status ssh` |

### Dentro de cada contenedor (vía Ansible)

| Nodo | Software instalado |
|------|---------------------|
| **app-api** | Python 3, FastAPI, uvicorn, dependencias en `app/requirements.txt` |
| **app-core** | Python 3, servicio core (`core_main.py`) |
| **db-postgres** | PostgreSQL 16, base `reservas`, usuario `lab` |
| **monitoring** | Prometheus, Grafana, node_exporter (en nodos scrapeados) |
| **node-control** | Paquetes base, SSH, utilidades lab |
| **ceph-node** | Demo montaje volumen ZFS (`ceph_demo` role) |
| **Todos (common)** | `curl`, `openssh-server`, **node_exporter** :9100 |

---

## 3. Contenedores y roles

Definidos en `lab.config.yaml`:

| Contenedor | IP | Rol | Puerto / servicio principal |
|------------|-----|-----|----------------------------|
| node-control | 10.10.0.10 | Control / semilla | SSH :22 |
| app-api | 10.10.0.20 | API REST | **8080** |
| app-core | 10.10.0.30 | Core validación | **8080** |
| db-postgres | 10.10.0.40 | Base de datos | **5432** |
| monitoring | 10.10.0.50 | Métricas + dashboards | **9090**, **3000** |
| ceph-node | 10.10.0.60 | Almacenamiento demo | volumen en `/var/lib/ceph-demo` |

### Ver estado

```bash
incus list
incus info app-api
incus exec app-api -- systemctl status reservas-api
incus exec db-postgres -- systemctl status postgresql
incus exec monitoring -- systemctl status prometheus grafana-server
```

### Entrar a un contenedor

```bash
incus exec app-api -- bash
incus exec monitoring -- bash
```

---

## 4. Red y conectividad

| Red | Rango / IP | Descripción |
|-----|------------|-------------|
| LAN | 192.168.1.129 | IP del host en tu red local |
| lab-br0 | 10.10.0.0/24 | Bridge Incus, gateway 10.10.0.1 |
| OVN | lab-ovn | Segmentación avanzada (demo) |

- **NAT:** salida a internet desde contenedores vía host.
- **Desde la Mac:** no hay ruta a 10.10.0.x → usar túnel SSH ([ACCESO-DESDE-MAC.md](ACCESO-DESDE-MAC.md)).

### Si cambia la IP del host

Incus guarda `core.https_address` con la IP antigua:

```bash
cd ~/incus-lab
./scripts/fix-incus-ip.sh
```

---

## 5. Estructura del repositorio

Ver detalle en [ESTRUCTURA-REPOSITORIO.md](ESTRUCTURA-REPOSITORIO.md).

Archivo central: **`lab.config.yaml`** — añadir/quitar nodos, CPU, RAM, IPs.

---

## 6. Comandos principales

### 6.1 Despliegue completo (recomendado para demo/entrega)

```bash
cd ~/incus-lab
./deploy-lab-full.sh
```

**Qué hace (7 fases):**

1. Corrige IP Incus + aplica contenedores (`lab-deploy.sh apply`)
2. OpenTofu idempotente (`deploy-phase2.sh tofu`)
3. Genera inventario Ansible + bootstrap SSH
4. Ansible `site.yml` en nodos app/db/monitoring/ceph
5. Demo OVN
6. Smoke test
7. Lista contenedores

Variables opcionales:

```bash
export DB_PASS="lab_secret_change_me"
export LAB_SSH_PASS="lab123"
./deploy-lab-full.sh
```

### 6.2 Stack mínimo (solo reservas)

```bash
cd ~/incus-lab
./start-reservas.sh
```

Arranca contenedores necesarios y despliega API + DB + monitoreo vía script bash.

### 6.3 Gestión Incus (`lab-deploy.sh`)

```bash
./lab-deploy.sh apply              # Todos los nodos enabled: true
./lab-deploy.sh apply app-api      # Un solo nodo
./lab-deploy.sh status             # Estado
./lab-deploy.sh inventory          # Genera generated/inventory.ini
./lab-deploy.sh start              # Arrancar nodos del config
./lab-deploy.sh stop
./lab-deploy.sh remove app-worker-1
./lab-deploy.sh prune              # Elimina nodos no definidos/deshabilitados
./lab-deploy.sh destroy            # Borra todos los nodos del lab
```

### 6.4 OpenTofu

```bash
cd ~/incus-lab/tofu
/snap/bin/tofu init
/snap/bin/tofu plan
/snap/bin/tofu apply
/snap/bin/tofu output
```

Importar recursos ya existentes:

```bash
./import-existing.sh
```

> El estado `terraform.tfstate` permanece en el servidor y **no** se sube a Git.

### 6.5 Ansible

```bash
cd ~/incus-lab
./scripts/gen-inventory.sh

# Solo validar sintaxis
ansible-playbook -i generated/inventory.ini ansible/playbooks/site.yml --syntax-check

# Despliegue completo
cd ansible
ansible-playbook -i ../generated/inventory.ini playbooks/site.yml

# Solo algunos nodos
ansible-playbook -i ../generated/inventory.ini playbooks/site.yml --limit app-api,monitoring
```

Bootstrap SSH (usuario temporal `ubuntu` / `lab123`):

```bash
./scripts/bootstrap-ssh.sh
```

### 6.6 Pruebas

```bash
bash scripts/smoke-test.sh          # Salud HTTP básica
bash scripts/test-api-crud.sh       # Auth + CRUD + eventos
curl http://10.10.0.20:8080/health
curl http://10.10.0.30:8080/health
```

### 6.7 Monitoreo

```bash
# Prometheus targets
curl -s http://10.10.0.50:9090/api/v1/targets | head

# Grafana — listar dashboards (en servidor)
incus exec monitoring -- curl -s -u admin:admin \
  http://127.0.0.1:3000/api/search?type=dash-db
```

**Dashboard:** *Lab Reservas Académicas* — UID `lab-reservas`  
URL directa (en servidor): `http://10.10.0.50:3000/d/lab-reservas/lab-reservas-academicas`

### 6.8 Logs y diagnóstico

```bash
incus exec app-api -- journalctl -u reservas-api -n 50 --no-pager
incus exec monitoring -- journalctl -u grafana-server -n 30 --no-pager
incus exec monitoring -- journalctl -u prometheus -n 30 --no-pager
./scripts/fix-network.sh
```

---

## 7. Aplicación (API)

Documentación detallada de endpoints: [README-RESERVAS.md](../README-RESERVAS.md).

| Concepto | Valor |
|----------|-------|
| Base URL (servidor) | http://10.10.0.20:8080 |
| Swagger | http://10.10.0.20:8080/docs |
| Login demo | `admin@lab.edu` / `lab123` |
| Base de datos | Host `10.10.0.40`, DB `reservas`, user `lab` |

### Flujo típico

```bash
# 1. Login
TOKEN=$(curl -s -X POST http://10.10.0.20:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@lab.edu","password":"lab123"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# 2. Listar recursos
curl -s -H "Authorization: Bearer $TOKEN" http://10.10.0.20:8080/resources

# 3. Métricas Prometheus
curl -s http://10.10.0.20:8080/metrics | head
```

---

## 8. Prometheus y Grafana

### Prometheus

- Config en contenedor: `/etc/prometheus/prometheus.yml`
- Alertas: `monitoring/prometheus/alerts-lab.yml` (repo) y template Ansible
- UI: http://10.10.0.50:9090

**Jobs típicos:** `reservas` (API/Core), `node` (node_exporter en nodos).

### Grafana

- Instalado vía paquete `.deb` en `monitoring`
- Datasource por defecto: **Prometheus-Lab** → `http://127.0.0.1:9090`
- Dashboard provisionado: `ansible/roles/grafana/files/lab-dashboard.json`
- Login: `admin` / `admin`

**Paneles del dashboard:**

- API UP / Core UP
- CPU nodos lab
- Reservas totales (`lab_reservations_total`)

---

## 9. Ansible — roles

| Rol | Función |
|-----|---------|
| `common` | Paquetes, usuario lab, node_exporter |
| `postgres` | PostgreSQL, schema, usuario DB |
| `app_service` | systemd FastAPI en app-api y app-core |
| `prometheus` | Config scrape y alertas |
| `grafana` | Instalación, datasource, dashboard |
| `ceph_demo` | Montaje demo en ceph-node |
| `validate` | Comprobaciones post-deploy |

Playbook principal: `ansible/playbooks/site.yml`

---

## 10. OpenTofu — recursos

| Archivo | Recursos |
|---------|----------|
| `network.tf` | Red `lab-br0`, OVN |
| `profile.tf` | Perfil Incus `lab` |
| `instances.tf` | Instancias alineadas con `lab.config.yaml` |
| `outputs.tf` | IPs y nombres exportados |

---

## 11. Sincronizar con GitHub

En el servidor:

```bash
cd ~/incus-lab
git status
git add .
git commit -m "docs: documentación completa y corrección dashboard Grafana"
git push origin main
```

Desde la Mac (si clonaste el repo):

```bash
cd ~/Desktop/incus-lab   # o tu ruta
git pull
```

**Remoto:** https://github.com/ErickCherry/Server-Incus

---

## 12. Solución de problemas

| Síntoma | Acción |
|---------|--------|
| Incus no arranca tras cambio de IP | `./scripts/fix-incus-ip.sh` |
| API no responde | `incus start app-api db-postgres` · `systemctl status reservas-api` |
| Grafana sin dashboards | Re-ejecutar rol grafana o reiniciar: `incus exec monitoring -- systemctl restart grafana-server` |
| Ansible falla SSH | `./scripts/bootstrap-ssh.sh` · verificar `generated/inventory.ini` |
| Mac no abre 10.10.0.x | Túnel SSH — [ACCESO-DESDE-MAC.md](ACCESO-DESDE-MAC.md) |
| Puerto 3000 ocupado en Mac | Usar puerto local 13000 en el túnel |

---

## 13. Referencias rápidas

| Recurso | Enlace / ruta |
|---------|----------------|
| Arquitectura visual | [ARQUITECTURA.md](ARQUITECTURA.md) |
| Entregables académicos | [ENTREGABLES.md](ENTREGABLES.md) |
| Acceso Mac | [ACCESO-DESDE-MAC.md](ACCESO-DESDE-MAC.md) |
| GitHub | https://github.com/ErickCherry/Server-Incus |
| Incus UI | https://192.168.1.129:8443 |
