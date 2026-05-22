# Entregables del proyecto — Guía paso a paso

Laboratorio: **Reservas académicas sobre Incus**  
Servidor: `server-fintek` — proyecto en `~/incus-lab`  
**Documentación completa:** [DOCUMENTACION.md](DOCUMENTACION.md) · **Repo:** https://github.com/ErickCherry/Server-Incus

---

## Mapa de entregables (qué hay en el repo)

| Entregable | Ubicación en el repo |
|------------|----------------------|
| Código de la aplicación | `app/` (`main.py`, `core_main.py`, `schema.sql`, `requirements.txt`) |
| OpenTofu (infraestructura) | `tofu/` (`*.tf`, `import-existing.sh`) |
| Ansible (config + despliegue) | `ansible/` (playbooks, roles, `group_vars`) |
| Scripts de automatización | `scripts/`, `lab-deploy.sh`, `deploy-phase2.sh`, `deploy-lab-full.sh` |
| Dashboards Grafana | `monitoring/grafana/dashboard-lab-reservas.json` |
| Reglas Prometheus | `monitoring/prometheus/alerts-lab.yml` |
| Diagrama y topología | `docs/ARQUITECTURA.md` |
| Config declarativa del lab | `lab.config.yaml` |

---

## Paso 0 — Conectarte al servidor

Desde tu Mac (ya configurado):

```bash
ssh fintek-local
# o: ssh fintek-1@192.168.1.129
```

```bash
cd ~/incus-lab
```

---

## Paso 1 — Verificar que el lab está arriba

```bash
cd ~/incus-lab
incus list
curl -s http://10.10.0.20:8080/health
curl -s http://10.10.0.50:9090/-/ready
curl -s -o /dev/null -w "%{http_code}\n" http://10.10.0.50:3000/login
```

Si algo falla:

```bash
./scripts/fix-incus-ip.sh    # si cambió la IP del host
./start-reservas.sh          # stack mínimo app
# o despliegue completo:
./deploy-lab-full.sh
```

---

## Paso 2 — Probar la aplicación (evidencia funcional)

```bash
bash ~/incus-lab/scripts/test-api-crud.sh
```

Documentación API: http://10.10.0.20:8080/docs

---

## Paso 3 — Exportar / copiar dashboards y Prometheus

### 3.1 Grafana (JSON del dashboard)

Ya está en el repo:

```bash
ls -la ~/incus-lab/monitoring/grafana/dashboard-lab-reservas.json
```

Para exportar de nuevo desde el contenedor (opcional):

```bash
incus exec monitoring -- cat /etc/grafana/provisioning/dashboards/lab-reservas.json \
  > ~/incus-lab/monitoring/grafana/dashboard-lab-reservas.json
```

Captura de pantalla para el informe (desde navegador en red del servidor):

- URL: http://10.10.0.50:3000  
- Usuario: `admin` / `admin`  
- Dashboard: **Lab Reservas Académicas**

### 3.2 Prometheus (config + alertas)

```bash
# Config activa en monitoring
incus exec monitoring -- cat /etc/prometheus/prometheus.yml \
  > ~/incus-lab/monitoring/prometheus/prometheus.yml

# Alertas (copia en repo)
ls ~/incus-lab/monitoring/prometheus/alerts-lab.yml
```

Ver targets en UI: http://10.10.0.50:9090/targets

---

## Paso 4 — OpenTofu (infraestructura como código)

```bash
cd ~/incus-lab/tofu
/snap/bin/tofu init
/snap/bin/tofu plan
/snap/bin/tofu output
```

Archivos que deben subirse a GitHub:

- `provider.tf`, `versions.tf`, `locals.tf`, `network.tf`, `profile.tf`, `instances.tf`, `outputs.tf`
- `import-existing.sh`
- **No subir** `terraform.tfstate` ni `.terraform/` (están en `.gitignore`)

---

## Paso 5 — Ansible (playbooks y roles)

```bash
cd ~/incus-lab
./scripts/gen-inventory.sh
cat generated/inventory.ini   # no commitear (tiene contraseña)

ansible-playbook -i generated/inventory.ini ansible/playbooks/site.yml --syntax-check
```

Entregable: carpeta completa `ansible/` + `generated/inventory.ini.example`

Despliegue documentado:

```bash
cd ~/incus-lab/ansible
ansible-playbook -i ../generated/inventory.ini playbooks/site.yml
```

---

## Paso 6 — Diagrama de arquitectura

Ver y exportar:

```bash
cat ~/incus-lab/docs/ARQUITECTURA.md
```

Para PDF/imagen: abre `ARQUITECTURA.md` en GitHub o en VS Code con vista Mermaid y exporta el diagrama.

---

## Paso 7 — Inicializar Git en el servidor

```bash
cd ~/incus-lab
git init
git branch -M main
git add .
git status
# Revisa que NO aparezcan: terraform.tfstate, .env, generated/inventory.ini
git commit -m "Entrega: app reservas académicas, OpenTofu, Ansible, monitoreo y documentación"
```

---

## Paso 8 — Subir a GitHub

Repo del proyecto: **https://github.com/ErickCherry/Server-Incus**

Para actualizar desde el servidor (recomendado: **SSH**, sin tokens en el repositorio):

```bash
cd ~/incus-lab
git pull origin main
# ... tus cambios ...
git add .
git commit -m "tu mensaje"
git push origin main
```

Configura en GitHub una **llave SSH** de despliegue (Settings → SSH keys). No guardes tokens ni contraseñas en archivos del repo.

---

## Paso 9 — Checklist final de entrega

- [ ] Repo GitHub público o privado con código
- [ ] `app/` con API documentada en README-RESERVAS.md
- [ ] `tofu/` sin state files
- [ ] `ansible/` con site.yml y roles
- [ ] `monitoring/grafana/` y `monitoring/prometheus/`
- [ ] `docs/ARQUITECTURA.md` con diagrama
- [ ] Scripts `deploy-lab-full.sh` y `test-api-crud.sh` probados
- [ ] Capturas: Swagger, Grafana, Prometheus targets (opcional en README)

---

## Comandos rápidos (resumen)

```bash
ssh fintek-local
cd ~/incus-lab
./deploy-lab-full.sh
bash scripts/test-api-crud.sh
git init && git add . && git commit -m "Entrega proyecto lab reservas"
git remote add origin https://github.com/TU_USUARIO/REPO.git
git push -u origin main
```
