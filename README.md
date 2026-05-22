# Laboratorio Incus — despliegue automatizado

Requisitos no funcionales cubiertos:

1. **Levantamiento sin intervención manual** — un solo comando aplica red, perfil, imagen y nodos.
2. **Escalar sin reescribir** — solo editas `lab.config.yaml` (añadir/quitar/deshabilitar nodos) y ejecutas `apply` o `remove`.

## Inicio rápido

```bash
cd ~/incus-lab
chmod +x lab-deploy.sh lib/*.sh
./lab-deploy.sh apply      # despliegue completo (idempotente)
./lab-deploy.sh status
./lab-deploy.sh inventory  # genera generated/inventory.ini para Ansible
```

## Añadir un nodo

Edita `lab.config.yaml`:

```yaml
  - name: app-worker-1
    role: worker
    ip: 10.10.0.70
    cpu: 1
    memory: 1GiB
    enabled: true
```

Luego:

```bash
./lab-deploy.sh apply app-worker-1
```

## Quitar un nodo (sin tocar el resto)

```bash
./lab-deploy.sh remove app-worker-1
```

O pon `enabled: false` en el YAML y ejecuta:

```bash
./lab-deploy.sh prune
```

## Reducir recursos de un nodo

Cambia `cpu` / `memory` en el YAML y:

```bash
./lab-deploy.sh apply nombre-nodo
```

(Incus aplicará límites; puede requerir reinicio del contenedor.)

## Comandos

| Comando | Descripción |
|---------|-------------|
| `apply` | Infraestructura + todos los nodos `enabled: true` |
| `apply <nodo>` | Solo ese nodo |
| `remove <nodo>` | Borra un contenedor |
| `prune` | Borra contenedores del lab no definidos o deshabilitados |
| `stop` / `start` | Parar o arrancar nodos del config |
| `destroy` | Elimina todos los nodos del config |
| `inventory` | Inventario Ansible en `generated/inventory.ini` |

## Fase 2 (Ansible / OpenTofu)

El inventario se regenera en cada `apply`. Desde `node-control`:

```bash
ansible all -i /path/to/generated/inventory.ini -m ping
```
