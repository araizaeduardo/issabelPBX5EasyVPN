# EasyVPN para Issabel 5

Este proyecto instala un módulo web para Issabel PBX 5 que permite administrar clientes OpenVPN, descargar perfiles `.ovpn`, revocar certificados y controlar el servicio `openvpn-server@easyvpn`. Incluye scripts auxiliares y una opción para aprovisionar un servidor OpenVPN/EasyRSA completamente funcional.

## Características principales

- **Módulo web** (`module/index.php`) para:
  - Crear, revocar y regenerar perfiles VPN.
  - Visualizar clientes conectados (auto-refresh cada 5 s).
  - Controlar el servicio (`Encender/Apagar/Reiniciar`) y mostrar su estado.
- **Scripts CLI** (`scripts/`) disponibles en `/usr/local/sbin/`:
  - `easyvpn-create-client.sh`
  - `easyvpn-revoke-client.sh`
  - `easyvpn-regenerate-profile.sh`
  - `easyvpn-status.sh`
  - `easyvpn-service.sh`
- **Instalador** (`install.sh`) que:
  - Copia el módulo y scripts con permisos adecuados.
  - Configura sudoers para permitir a `asterisk` ejecutar los scripts.
  - Prepara el archivo `easyvpn-status.log` para `status-version 2`.
  - Opcionalmente instala y configura OpenVPN/EasyRSA (`--with-server`).

## Requisitos

- Issabel PBX 5 (basado en Rocky/Alma Linux 8).
- Acceso a la consola con privilegios de `root`.
- Paquetes: `openvpn`, `easy-rsa`, `sqlite`, `systemd` (instalados automáticamente con `--with-server`).

## Instalación

Descargar y descomprimir el paquete:

```bash
unzip easyvpn-issabel5.zip
cd easyvpn-issabel5
chmod +x install.sh
```

### 1. Solo módulo y scripts

Si ya cuentas con OpenVPN configurado (certificados, servicio y `status-version 2` en `/var/log/openvpn/easyvpn-status.log`):

```bash
./install.sh
```

### 2. Instalación completa con servidor EasyVPN

Para preparar OpenVPN/EasyRSA, generar certificados y dejar el servicio listo:

```bash
./install.sh --with-server
```

Este modo:

- Crea la estructura `/etc/openvpn/easyvpn/` con PKI EasyRSA.
- Instala `openvpn-server@easyvpn.service` y lo habilita.
- Configura `/etc/openvpn/server/easyvpn.conf` con `status-version 2`.
- Instala `client-template.ovpn` listo para personalizar.

## Funcionamiento del módulo

- Los perfiles generados se guardan en `/etc/openvpn/easyvpn/generated/`.
- Los archivos de estado de clientes se leen desde `/var/log/openvpn/easyvpn-status.log`.
- La barra superior muestra el estado del servicio y permite controlarlo.
- El listado de clientes conectados se refresca automáticamente sin recargar la página.

## Actualizaciones manuales

- Tras modificar el código del módulo, volver a ejecutar `./install.sh` para desplegar cambios.
- Si se requiere reinstalar con servidor, usar `./install.sh --with-server` (idempotente, no sobrescribe PKI existente).

## Desinstalación rápida

1. Eliminar el módulo web: `rm -rf /var/www/html/modules/easyvpn`.
2. Eliminar scripts: `rm -f /usr/local/sbin/easyvpn-*`.
3. Limpiar sudoers: `rm -f /etc/sudoers.d/easyvpn`.
4. Opcional: detener/eliminar `openvpn-server@easyvpn` y borrar `/etc/openvpn/easyvpn/`.

## Soporte

Este repositorio se entrega “tal cual”. Verifica los permisos y políticas de tu organización antes de usarlo en producción.
