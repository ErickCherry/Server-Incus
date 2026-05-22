# Seguridad, red estática y recuperación

## IP estática en el router (reserva DHCP)

En el router (192.168.1.1 o la IP de tu gateway):

1. Entra a la interfaz web del router (suele ser http://192.168.1.1).
2. Busca **DHCP** → **Reserva DHCP** / **Static DHCP** / **Address reservation**.
3. Añade una reserva con:
   - **MAC:** `e8:d8:d1:b8:7a:08` (interfaz `enp2s0` del server-fintek)
   - **IP:** `192.168.1.129`
   - **Nombre:** `server-fintek` (opcional)
4. Guarda y reinicia el router si lo pide.

Así el servidor siempre recibe la misma IP aunque use DHCP.

## IP estática en Ubuntu (netplan)

Archivo recomendado: `/etc/netplan/01-lab-static.yaml`

```yaml
network:
  version: 2
  ethernets:
    enp2s0:
      dhcp4: false
      addresses:
        - 192.168.1.129/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [192.168.1.1, 8.8.8.8, 1.1.1.1]
```

Desactiva DHCP en cloud-init (opcional):

```bash
sudo sed -i 's/dhcp4: true/dhcp4: false/' /etc/netplan/50-cloud-init.yaml
sudo netplan try    # confirma en 120 s o revierte
sudo netplan apply
```

> Usa `netplan try` antes de `apply` para no perder acceso remoto.

## Si perdiste conexión SSH tras netplan

Desde **monitor y teclado** del servidor:

```bash
# Volver a DHCP temporalmente
sudo tee /etc/netplan/01-lab-static.yaml << 'EOF'
network:
  version: 2
  ethernets:
    enp2s0:
      dhcp4: true
EOF
sudo netplan apply
```

Cuando vuelva la red, aplica la IP estática con `netplan try`.

## Secretos del laboratorio

| Archivo | Ubicación |
|---------|-----------|
| Secretos reales | `~/incus-lab/secrets/lab.secrets.env` (solo servidor, **600**) |
| Plantilla sin claves | `secrets/lab.secrets.env.example` |

Nunca subas `secrets/lab.secrets.env` a GitHub.

## Firewall (UFW)

Solo red local:

- **Permitido:** SSH (22) y Incus UI (8443) desde `192.168.1.0/24`
- **Bloqueado:** Incus 8443 desde Internet
- Los servicios del lab (8080, 3000, 9090) están en `10.10.0.x` y no se publican en la LAN del host

```bash
sudo ufw status verbose
```

## SSH del host

- Solo usuario `fintek-1`
- **Sin contraseña SSH** — solo llave pública (`~/.ssh/authorized_keys`)
- Mantén tu llave en la Mac; sin llave no entrarás

## Recuperación automática tras apagón

Servicio systemd: `incus-lab-recovery.service`

```bash
sudo systemctl status incus-lab-recovery.service
sudo systemctl enable incus-lab-recovery.service
```

Script: `scripts/lab-recovery.sh` — corrige IP Incus, arranca contenedores, valida API.

Contenedores con `boot.autostart=true` en Incus.

## Grabación de video y GitHub

- No muestres `secrets/lab.secrets.env` ni contraseñas en pantalla.
- En GitHub no hay contraseñas reales (solo plantillas).
- Para demos en video usa credenciales rotadas y cámbialas después si se filtraron.

## Acceso desde la Mac

Ver [ACCESO-DESDE-MAC.md](ACCESO-DESDE-MAC.md) — túnel SSH a `127.0.0.1`, no expongas puertos del lab a Internet.
