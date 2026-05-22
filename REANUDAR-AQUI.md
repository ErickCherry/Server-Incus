# Punto de control — Laboratorio Incus (guardado antes del apagado)

**Fecha de cierre:** 2026-05-21  
**Servidor:** `server-fintek` — Ubuntu 24.04.4 LTS  
**IP del host:** `192.168.1.129`  
**Usuario SSH:** `fintek-1`  
**Proyecto en disco:** `/home/fintek-1/incus-lab/`

---

## Qué quedó guardado (persiste en disco)

| Componente | Ubicación | Notas |
|------------|-----------|--------|
| Config declarativa del lab | `lab.config.yaml` | 6 nodos, red 10.10.0.0/24 |
| Scripts automatización | `lab-deploy.sh`, `lib/`, `scripts/` | Crear/ampliar nodos sin manual |
| OpenTofu (IaC) | `tofu/` + `terraform.tfstate` | Red, perfil, instancias importadas |
| Ansible (fase 2) | `ansible/` | Roles: common, app, postgres, prometheus, grafana |
| App reservas (código) | `app/` | API FastAPI + schema SQL + core |
| Despliegue app | `scripts/deploy-reservas-app.sh` | **Pendiente terminar** (ver abajo) |
| Incus (contenedores, ZFS, redes) | `/var/lib/incus/` | Sobrevive reinicio/apagado |
| Imagen local | `ubuntu2404` | En pool ZFS `default` |
| Redes Incus | `lab-br0`, `lab-ovn` | Definición en base de datos Incus |
| Perfil | `lab` | eth0 → lab-br0, disco ZFS |
| Fix Incus daemon | `core.https_address` | `192.168.1.129:8443` (en DB Incus) |
| UFW | reglas persistentes | Forward `lab-br0` ↔ `enp2s0` |

---

## Nodos desplegados

| Nodo | IP | Rol | Estado al apagar |
|------|-----|-----|------------------|
| node-control | 10.10.0.10 | control | Contenedor creado |
| app-api | 10.10.0.20 | api | Contenedor creado |
| app-core | 10.10.0.30 | core | Contenedor creado |
| db-postgres | 10.10.0.40 | database | PostgreSQL **instalado** (schema puede estar incompleto) |
| monitoring | 10.10.0.50 | monitoring | Contenedor creado |
| ceph-node | 10.10.0.60 | storage | Contenedor creado |

---

## Completado vs pendiente

### Hecho
- [x] Incus operativo (reparado bind IP)
- [x] Red `lab-br0` 10.10.0.0/24 + OVN `lab-ovn`
- [x] Perfil `lab` y pool ZFS `default`
- [x] 6 contenedores con IPs fijas y conectividad interna
- [x] UFW: forward para DNS/NAT del lab
- [x] OpenTofu init + import + state
- [x] Estructura Ansible fase 2
- [x] Código app reservas académicas (auth, CRUD recursos/reservas, event_logs)

### Pendiente (continuar aquí)
- [ ] Terminar `scripts/deploy-reservas-app.sh` (falló quoting SQL en PostgreSQL)
- [ ] Ansible `deploy-phase2.sh ansible` (SSH/LXC no terminado)
- [ ] Validación Prometheus/Grafana con métricas de la API
- [ ] Prueba E2E: login `admin@lab.edu` / `lab123`

---

## Cómo volver a conectar el agente de Cursor

### Opción A — Remote SSH (recomendada)

1. Enciende el servidor y espera ~1 minuto.
2. En Cursor: **File → Connect to Host…** (o Remote-SSH).
3. Conéctate a:
   ```text
   fintek-1@192.168.1.129
   ```
4. Abre la carpeta del proyecto:
   ```text
   /home/fintek-1/incus-lab
   ```
5. En el chat, di por ejemplo:
   > Continúa desde REANUDAR-AQUI.md — termina la app de reservas y validación.

No hace falta “guardar la conexión” en Cursor: al abrir Remote SSH al mismo host y carpeta, el agente ve los mismos archivos y este documento.

### Opción B — Misma máquina local

Si Cursor ya estaba en SSH remoto a este servidor, solo reconecta cuando el host esté encendido y vuelve a abrir `/home/fintek-1/incus-lab`.

---

## Comandos tras encender el servidor (en orden)

```bash
# 1. Verificar Incus
systemctl status incus
incus list

# 2. Si los contenedores están STOPPED, arrancarlos
incus start node-control app-api app-core db-postgres monitoring ceph-node

# 3. Red y UFW (por si acaso)
sudo ufw route allow in on lab-br0 out on enp2s0
sudo ufw route allow in on enp2s0 out on lab-br0
sudo ip link set lab-br0 up

# 4. Reaplicar lab idempotente
cd ~/incus-lab
./lab-deploy.sh apply
./lab-deploy.sh status

# 5. Continuar fase 2 / app
./scripts/deploy-reservas-app.sh    # terminar app reservas
# o: ./deploy-phase2.sh ansible

# 6. Incus UI (opcional, en el host)
incus admin ui
```

---

## URLs del laboratorio (cuando la app esté desplegada)

| Servicio | URL |
|----------|-----|
| API + Swagger | http://10.10.0.20:8080/docs |
| Core health | http://10.10.0.30:8080/health |
| Prometheus | http://10.10.0.50:9090 |
| Grafana | http://10.10.0.50:3000 (admin/admin por defecto) |
| Incus API (host) | https://192.168.1.129:8443 |

**Credenciales demo app:** `admin@lab.edu` / `lab123`  
**DB:** host `10.10.0.40`, db `reservas`, user `lab`, pass `lab_secret_change_me`

---

## Archivos clave

```
~/incus-lab/
├── REANUDAR-AQUI.md          ← ESTE ARCHIVO
├── lab.config.yaml
├── lab-deploy.sh
├── deploy-phase2.sh
├── app/                      ← API reservas
├── ansible/
├── tofu/
└── scripts/
    ├── deploy-reservas-app.sh
    ├── fix-network.sh
    └── gen-inventory.sh
```

---

## Apagado realizado

El host se apagó con `shutdown` ordenado. Los contenedores se detuvieron antes del apagado para dejar ZFS consistente. **No se borró** `/var/lib/incus` ni el proyecto en `~/incus-lab`.

---

## Actualización 2026-05-22 (reanudado)

- **IP LAN actual:** `192.168.1.129` (Incus `core.https_address` corregido en `local.db`)
- **Incus:** activo, 6 contenedores RUNNING
- **App reservas:** API + Core OK, login `admin@lab.edu` / `lab123`, reserva E2E creada
- **Fix login:** `verify_password` usa `stored[6:]` para prefijo `plain:`
- **Pendiente menor:** Grafana (paquete no en repos Ubuntu del contenedor); Prometheus instalado en monitoring

### Si Incus no arranca tras cambio de IP

```bash
sudo sqlite3 /var/lib/incus/database/local.db \
  "UPDATE config SET value='192.168.1.129:8443' WHERE key IN ('core.https_address','cluster.https_address');"
sudo systemctl restart incus
```

## Stack mínimo reservas (2026-05-22)

**Un comando:** 

Nodos: app-api, app-core, db-postgres, monitoring (node-control y ceph-node opcionales).

| Servicio | URL |
|----------|-----|
| API | http://10.10.0.20:8080/docs |
| Core | http://10.10.0.30:8080/health |
| Prometheus | http://10.10.0.50:9090 |
| Grafana | http://10.10.0.50:3000 |

Ver también: README-RESERVAS.md

## Completado 2026-05-22 (ítems 1–5)

- [x] Ansible: roles alineados con FastAPI + postgres + prometheus + grafana + ceph_demo + validate
- [x] Prometheus alertas + scrape 4 nodos + API/Core
- [x] Grafana repo oficial + dashboard Lab Reservas
- [x] deploy-lab-full.sh + smoke-test.sh + fix-incus-ip + ovn-demo
- [x] Validación Ansible + smoke OK
- [ ] Funcionalidades de negocio extra (definir contigo — ver README-RESERVAS.md)
