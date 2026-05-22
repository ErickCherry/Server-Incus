# Server-Incus — Laboratorio reservas académicas

Repositorio del proyecto **Incus + OpenTofu + Ansible + FastAPI + Prometheus/Grafana** desplegado en `server-fintek`.

**Repositorio:** https://github.com/ErickCherry/Server-Incus

---

## Documentación

| Documento | Contenido |
|-----------|-----------|
| [docs/DOCUMENTACION.md](docs/DOCUMENTACION.md) | **Guía principal:** instalado, contenedores, comandos, despliegue, API, monitoreo |
| [docs/ESTRUCTURA-REPOSITORIO.md](docs/ESTRUCTURA-REPOSITORIO.md) | Árbol de carpetas y archivos clave |
| [docs/ARQUITECTURA.md](docs/ARQUITECTURA.md) | Diagramas Mermaid y topología de red |
| [docs/ACCESO-DESDE-MAC.md](docs/ACCESO-DESDE-MAC.md) | Túnel SSH para abrir API/Grafana desde tu Mac |
| [README-RESERVAS.md](README-RESERVAS.md) | API de reservas, endpoints y credenciales demo |
| [docs/ENTREGABLES.md](docs/ENTREGABLES.md) | Checklist de entrega académica y grabación de video |

---

## Inicio rápido (en el servidor)

```bash
cd ~/incus-lab
./deploy-lab-full.sh          # Todo: Incus, Tofu, Ansible, OVN, pruebas
# o solo app mínima:
./start-reservas.sh
bash scripts/test-api-crud.sh
```

---

## Contenedores del lab

| Nodo | IP | Servicios |
|------|-----|-----------|
| node-control | 10.10.0.10 | Nodo semilla / control |
| app-api | 10.10.0.20 | FastAPI :8080 |
| app-core | 10.10.0.30 | Core :8080 |
| db-postgres | 10.10.0.40 | PostgreSQL :5432 |
| monitoring | 10.10.0.50 | Prometheus :9090, Grafana :3000 |
| ceph-node | 10.10.0.60 | Demo almacenamiento ZFS |

Red interna: `lab-br0` → `10.10.0.0/24` · Host LAN: `192.168.1.129`

---

## URLs (desde el servidor)

| Servicio | URL |
|----------|-----|
| API Swagger | http://10.10.0.20:8080/docs |
| Prometheus | http://10.10.0.50:9090 |
| Grafana | http://10.10.0.50:3000 |
| Incus UI | https://192.168.1.129:8443 |

Desde la Mac: ver [docs/ACCESO-DESDE-MAC.md](docs/ACCESO-DESDE-MAC.md).

---

## Escalar el lab

Edita `lab.config.yaml` y ejecuta:

```bash
./lab-deploy.sh apply
./lab-deploy.sh inventory
```

Ver [docs/DOCUMENTACION.md](docs/DOCUMENTACION.md) para todos los comandos.
