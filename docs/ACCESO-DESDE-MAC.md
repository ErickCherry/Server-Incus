# Acceso desde la Mac al laboratorio

Las IPs `10.10.0.x` son **solo internas** del bridge Incus en el servidor. Tu Mac **no** puede abrir `http://10.10.0.20:8080` directamente.

## Túnel SSH (recomendado)

En una terminal de la Mac (déjala abierta):

```bash
ssh -N \
  -L 8080:10.10.0.20:8080 \
  -L 3000:10.10.0.50:3000 \
  -L 9090:10.10.0.50:9090 \
  fintek-local
```

Si aparece `Address already in use`, el túnel **ya está activo** — usa las URLs de abajo sin volver a ejecutar `ssh`.

### URLs en la Mac

| Servicio | URL |
|----------|-----|
| API Swagger | http://127.0.0.1:8080/docs |
| Grafana | http://127.0.0.1:3000 |
| Dashboard Lab | http://127.0.0.1:3000/d/lab-reservas/lab-reservas-academicas |
| Prometheus | http://127.0.0.1:9090 |

**Grafana:** `admin` / `admin`

### Comprobar

```bash
curl http://127.0.0.1:8080/health
```

## Puertos alternativos

Si el puerto 3000 está ocupado por otra app (p. ej. Node):

```bash
ssh -N \
  -L 18080:10.10.0.20:8080 \
  -L 13000:10.10.0.50:3000 \
  -L 19090:10.10.0.50:9090 \
  fintek-local
```

- API: http://127.0.0.1:18080/docs  
- Grafana: http://127.0.0.1:13000  

## Configuración SSH permanente (opcional)

En `~/.ssh/config`, bloque `Host fintek-local`:

```
    LocalForward 8080 10.10.0.20:8080
    LocalForward 3000 10.10.0.50:3000
    LocalForward 9090 10.10.0.50:9090
```

Luego: `ssh fintek-local` activa los túneles automáticamente.

## Conexión al servidor

```bash
ssh fintek-local
# Host: 192.168.1.129 · Usuario: fintek-1
cd ~/incus-lab
```
