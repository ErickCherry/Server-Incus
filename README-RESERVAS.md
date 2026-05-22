# App de reservas académicas — stack mínimo

## Nodos requeridos

| Nodo | IP | Rol |
|------|-----|-----|
| app-api | 10.10.0.20 | API FastAPI + métricas |
| app-core | 10.10.0.30 | Validación / enlace con API |
| db-postgres | 10.10.0.40 | PostgreSQL |
| monitoring | 10.10.0.50 | Prometheus + Grafana |

## Arranque (un comando)

```bash
cd ~/incus-lab
./start-reservas.sh
```

## URLs

- **Swagger API:** http://10.10.0.20:8080/docs
- **Health API:** http://10.10.0.20:8080/health
- **Core:** http://10.10.0.30:8080/health
- **Prometheus:** http://10.10.0.50:9090
- **Grafana:** http://10.10.0.50:3000 (admin / admin)

## Credenciales demo

- Email: `admin@lab.edu`
- Password: `lab123`

## Prueba rápida

```bash
curl -s http://10.10.0.20:8080/health
curl -s -X POST http://10.10.0.20:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@lab.edu","password":"lab123"}'
```

## Infraestructura usada

- **Incus:** contenedores y red `lab-br0`
- **OpenTofu:** definición en `tofu/` (estado persistido)
- **Ansible:** roles en `ansible/` (fase opcional; deploy actual vía script)
- **Monitoreo:** Prometheus scrape node_exporter + `/metrics` de API/Core

## Funcionalidades API actuales (base para ampliar)

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | /health | Estado API + DB |
| GET | /metrics | Métricas Prometheus |
| POST | /auth/login | Token (admin@lab.edu / lab123) |
| GET/POST | /resources | Listar / crear laboratorios |
| GET/PUT/DELETE | /resources/{id} | Detalle / editar / borrar |
| GET/POST | /reservations | Listar / crear reservas |
| GET/PUT/DELETE | /reservations/{id} | Gestionar reserva |
| GET | /events | Auditoría (event_logs) |

Core: `/health`, `/metrics` — valida que la API responda.

## Despliegue completo (puntos 1–5)

```bash
cd ~/incus-lab
./deploy-lab-full.sh
```

## Funcionalidades implementadas (v1.1)

### 1. Autenticación básica
| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | /auth/login | Obtiene token Bearer |
| POST | /auth/logout | Cierra sesión (invalida token) |
| GET | /auth/me | Usuario autenticado |

Todas las rutas de recursos, reservas y eventos requieren header: `Authorization: Bearer <token>`.

### 2. CRUD recursos académicos
| Método | Ruta |
|--------|------|
| GET | /resources |
| POST | /resources |
| GET | /resources/{id} |
| PUT | /resources/{id} |
| DELETE | /resources/{id} |

### 3. CRUD reservas
| Método | Ruta |
|--------|------|
| GET | /reservations (?resource_id, ?status) |
| POST | /reservations |
| GET | /reservations/{id} |
| PUT | /reservations/{id} |
| DELETE | /reservations/{id} |

Validaciones: fechas coherentes, sin solapamiento de horario, recurso disponible.

### 4. Registro de eventos y errores
| Método | Ruta |
|--------|------|
| GET | /events (?level, ?source, ?limit) |
| GET | /events/errors | Solo nivel error |

Se registran: logins, CRUD, HTTP 4xx/5xx, errores de validación y excepciones internas (tabla `event_logs`).

### Prueba automática
```bash
bash ~/incus-lab/scripts/test-api-crud.sh
```
