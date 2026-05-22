# Arquitectura y topología — Lab reservas académicas

## 1. Vista general

```mermaid
flowchart TB
  subgraph LAN["Red local 192.168.1.0/24"]
    DEV["PC desarrollo / Cursor SSH"]
    HOST["server-fintek 192.168.1.129"]
  end

  subgraph HOST_INCUS["Host — Incus + OpenTofu + Ansible"]
    INCUS["Incus daemon"]
    TOFU["OpenTofu state"]
    ANS["Ansible playbooks"]
  end

  subgraph LAB["Red lab-br0 10.10.0.0/24"]
    API["app-api 10.10.0.20\nFastAPI :8080"]
    CORE["app-core 10.10.0.30\nCore :8080"]
    DB["db-postgres 10.10.0.40\nPostgreSQL :5432"]
    MON["monitoring 10.10.0.50\nPrometheus :9090\nGrafana :3000"]
    CTL["node-control 10.10.0.10"]
    CEPH["ceph-node 10.10.0.60\nvol ZFS demo"]
  end

  DEV -->|SSH 22| HOST
  HOST --> INCUS
  TOFU --> INCUS
  ANS -->|SSH 10.10.0.x| API
  ANS --> DB
  ANS --> MON
  INCUS --> LAB
  API -->|SQL| DB
  CORE -->|HTTP health| API
  MON -->|scrape /metrics| API
  MON -->|scrape /metrics| CORE
  MON -->|node_exporter :9100| API
```

## 2. Topología de red

| Capa | Elemento | IP / rango | Rol |
|------|----------|------------|-----|
| Física/LAN | server-fintek | 192.168.1.129 | Host Ubuntu 24.04 |
| Bridge Incus | lab-br0 | 10.10.0.1/24 | NAT, DHCP lab |
| OVN (definido) | lab-ovn | sobre lab-br0 | Segmentación avanzada |
| Contenedor | app-api | 10.10.0.20 | API REST + auth + CRUD |
| Contenedor | app-core | 10.10.0.30 | Validación / proxy lógico |
| Contenedor | db-postgres | 10.10.0.40 | Persistencia |
| Contenedor | monitoring | 10.10.0.50 | Observabilidad |
| Contenedor | node-control | 10.10.0.10 | Nodo control |
| Contenedor | ceph-node | 10.10.0.60 | Almacenamiento demo |

## 3. Flujo de despliegue (IaC + config)

```mermaid
sequenceDiagram
  participant Op as Operador
  participant T as OpenTofu
  participant I as Incus
  participant A as Ansible
  participant App as app-api

  Op->>T: tofu apply (red, perfil, instancias)
  T->>I: Crear/actualizar recursos
  Op->>A: ansible-playbook site.yml
  A->>App: Instalar Python, systemd, DB
  Op->>App: POST /auth/login
```

## 4. Flujo de datos de la aplicación

```mermaid
sequenceDiagram
  participant U as Usuario
  participant API as app-api
  participant DB as PostgreSQL
  participant EV as event_logs

  U->>API: POST /auth/login
  API->>DB: validar usuario
  API->>EV: log info auth
  U->>API: CRUD /resources /reservations
  API->>DB: SQL
  API->>EV: log info/warning/error
```

## 5. Stack de monitoreo

| Componente | Puerto | Qué mide |
|------------|--------|----------|
| node_exporter | 9100 | CPU, RAM, disco (por nodo) |
| API /metrics | 8080 | lab_reservations_total, lab_up |
| Core /metrics | 8080 | lab_core_up |
| Prometheus | 9090 | Scraping + alertas |
| Grafana | 3000 | Dashboard Lab Reservas |

Alertas definidas: `monitoring/prometheus/alerts-lab.yml` (ApiDown, CoreDown, HighNodeCPU).

## 6. Almacenamiento

- **Pool ZFS** `default` en el host Incus.
- Volúmenes: `db-data` → PostgreSQL, `ceph-data` → demo en ceph-node.
- Ceph: capa **didáctica** (no cluster Ceph productivo).

## 7. URLs de referencia

| Servicio | URL |
|----------|-----|
| API Swagger | http://10.10.0.20:8080/docs |
| Prometheus | http://10.10.0.50:9090 |
| Grafana | http://10.10.0.50:3000 |
| Incus UI | https://192.168.1.129:8443 |
