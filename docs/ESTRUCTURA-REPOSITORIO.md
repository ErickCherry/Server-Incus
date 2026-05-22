# Estructura del repositorio

```
Server-Incus/
├── README.md                 # Índice principal
├── README-RESERVAS.md        # API y credenciales
├── REANUDAR-AQUI.md          # Checkpoint operativo del lab
├── lab.config.yaml           # Definición de nodos, red y recursos (fuente de verdad)
├── lab-deploy.sh             # Orquestador Incus (apply/remove/inventory)
├── deploy-lab-full.sh        # Despliegue completo automatizado
├── deploy-phase2.sh          # OpenTofu + fases adicionales
├── start-reservas.sh         # Stack mínimo (API + DB + monitoreo)
│
├── app/                      # Código fuente aplicación
│   ├── main.py               # API FastAPI (auth, CRUD, eventos)
│   ├── core_main.py          # Servicio core
│   ├── schema.sql            # Esquema PostgreSQL
│   └── requirements.txt
│
├── tofu/                     # Infraestructura como código (OpenTofu)
│   ├── provider.tf
│   ├── network.tf            # Red lab-br0, OVN
│   ├── profile.tf            # Perfil Incus
│   ├── instances.tf          # Instancias/contenedores
│   ├── outputs.tf
│   └── import-existing.sh
│
├── ansible/                  # Configuración y despliegue
│   ├── ansible.cfg
│   ├── playbooks/
│   │   ├── site.yml          # Playbook principal
│   │   └── bootstrap-ssh.yml
│   └── roles/
│       ├── common/           # Paquetes base, node_exporter
│       ├── postgres/         # PostgreSQL
│       ├── app_service/      # systemd + FastAPI
│       ├── prometheus/
│       ├── grafana/
│       ├── ceph_demo/
│       └── validate/
│
├── scripts/                  # Utilidades operativas
│   ├── gen-inventory.sh      # Genera generated/inventory.ini
│   ├── bootstrap-ssh.sh
│   ├── deploy-reservas-app.sh
│   ├── test-api-crud.sh
│   ├── smoke-test.sh
│   ├── fix-incus-ip.sh
│   └── ovn-demo.sh
│
├── lib/                      # Librerías bash de lab-deploy
│   ├── common.sh
│   ├── network.sh
│   └── nodes.sh
│
├── monitoring/               # Entregables observabilidad (copia en repo)
│   ├── grafana/dashboard-lab-reservas.json
│   └── prometheus/alerts-lab.yml
│
├── docs/                     # Documentación
│   ├── DOCUMENTACION.md
│   ├── ARQUITECTURA.md
│   ├── ESTRUCTURA-REPOSITORIO.md
│   ├── ACCESO-DESDE-MAC.md
│   └── ENTREGABLES.md
│
└── generated/                # Generado en runtime (parcial en repo)
    ├── inventory.ini.example # Plantilla (inventory.ini real está en .gitignore)
    └── incus-*-snapshot.*    # Snapshots de estado Incus
```

## Archivos que NO se suben a Git (`.gitignore`)

| Archivo | Motivo |
|---------|--------|
| `tofu/terraform.tfstate` | Estado local con datos sensibles |
| `tofu/.terraform/` | Plugins descargados |
| `generated/inventory.ini` | Contiene contraseña SSH del lab |
| `.env` | Secretos |

## Entregables académicos → carpetas

| Entregable | Ubicación |
|------------|-----------|
| Código aplicación | `app/` |
| OpenTofu | `tofu/` |
| Ansible | `ansible/` |
| Dashboard Grafana | `monitoring/grafana/` + `ansible/roles/grafana/` |
| Alertas Prometheus | `monitoring/prometheus/` + `ansible/roles/prometheus/` |
| Arquitectura | `docs/ARQUITECTURA.md` |
