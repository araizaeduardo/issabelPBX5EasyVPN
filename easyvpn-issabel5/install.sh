install_default_settings() {
  local script_dir="$1"

  mkdir -p "${EASYVPN_DIR}"

  if [[ -f "${SETTINGS_FILE}" ]]; then
    echo "-> Archivo de settings ya presente en ${SETTINGS_FILE}, no se sobrescribe."
    return
  fi

  if [[ -f "${script_dir}/config/easyvpn-settings.conf" ]]; then
    echo "-> Instalando configuración base en ${SETTINGS_FILE} ..."
    install -o root -g asterisk -m 640 "${script_dir}/config/easyvpn-settings.conf" "${SETTINGS_FILE}"
  else
    echo "-> Archivo de configuración base no encontrado; se omitirá (${script_dir}/config/easyvpn-settings.conf)."
    touch "${SETTINGS_FILE}"
    chown root:asterisk "${SETTINGS_FILE}"
    chmod 640 "${SETTINGS_FILE}"
  fi
}

register_acl_and_menu() {
  echo "-> Registrando ACL y menú en Issabel ..."

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "   WARNING: sqlite3 no disponible, omitiendo registro." >&2
    return
  fi

  if [[ -f "${ACL_DB}" ]]; then
    sqlite3 "${ACL_DB}" "CREATE TABLE IF NOT EXISTS acl_resource (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR(128) UNIQUE, description VARCHAR(255));"
    sqlite3 "${ACL_DB}" "INSERT OR IGNORE INTO acl_resource (name, description) VALUES ('easyvpn', 'EasyVPN Module');"
  else
    echo "   WARNING: No se encontró ${ACL_DB}, omitiendo ACL." >&2
  fi

  if [[ -f "${MENU_DB}" ]]; then
    sqlite3 "${MENU_DB}" "CREATE TABLE IF NOT EXISTS menu (id varchar(40) PRIMARY KEY, IdParent varchar(40), Link varchar(250), Name varchar(250), Type varchar(20), order_no Integer);"
    sqlite3 "${MENU_DB}" "INSERT OR REPLACE INTO menu (id, IdParent, Link, Name, Type, order_no) VALUES ('easyvpn', 'security', 'modules/easyvpn/index.php', 'EasyVPN', 'module', 50);"
  else
    echo "   WARNING: No se encontró ${MENU_DB}, omitiendo menú." >&2
  fi
}

SETTINGS_FILE="${EASYVPN_DIR}/easyvpn-settings.conf"
ACL_DB="/var/www/db/acl.db"
MENU_DB="/var/www/db/menu.db"

#!/usr/bin/env bash
set -euo pipefail

MODULE_NAME="easyvpn"
ISSABEL_MODULE_DIR="/var/www/html/modules/${MODULE_NAME}"
SCRIPTS_TARGET_DIR="/usr/local/sbin"

EASYVPN_DIR="/etc/openvpn/easyvpn"
EASYVPN_KEYS_DIR="${EASYVPN_DIR}/keys"
EASYVPN_GENERATED_DIR="${EASYVPN_DIR}/generated"
EASYVPN_CCD_DIR="${EASYVPN_DIR}/ccd"
SERVER_CONF_DIR="/etc/openvpn/server"
SERVER_CONF="${SERVER_CONF_DIR}/easyvpn.conf"
STATUS_LOG="/var/log/openvpn/easyvpn-status.log"
SUDOERS_FILE="/etc/sudoers.d/easyvpn"

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
  fi
}

install_module() {
  local script_dir="$1"

  echo "-> Instalando módulo web en ${ISSABEL_MODULE_DIR} ..."
  mkdir -p "${ISSABEL_MODULE_DIR}/libs" "${ISSABEL_MODULE_DIR}/css"

  cp "${script_dir}/module/index.php" "${ISSABEL_MODULE_DIR}/index.php"
  cp "${script_dir}/module/libs/easyvpn.php" "${ISSABEL_MODULE_DIR}/libs/easyvpn.php"
  cp "${script_dir}/module/css/style.css" "${ISSABEL_MODULE_DIR}/css/style.css"

  chown -R root:asterisk "${ISSABEL_MODULE_DIR}"
  find "${ISSABEL_MODULE_DIR}" -type d -exec chmod 750 {} \;
  find "${ISSABEL_MODULE_DIR}" -type f -exec chmod 640 {} \;

  echo "   Módulo web instalado."
}

install_scripts() {
  local script_dir="$1"

  echo "-> Instalando scripts en ${SCRIPTS_TARGET_DIR} ..."
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-create-client.sh"      "${SCRIPTS_TARGET_DIR}/easyvpn-create-client.sh"
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-revoke-client.sh"      "${SCRIPTS_TARGET_DIR}/easyvpn-revoke-client.sh"
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-regenerate-profile.sh" "${SCRIPTS_TARGET_DIR}/easyvpn-regenerate-profile.sh"
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-status.sh"             "${SCRIPTS_TARGET_DIR}/easyvpn-status.sh"
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-service.sh"            "${SCRIPTS_TARGET_DIR}/easyvpn-service.sh"
  install -o root -g root -m 750 "${script_dir}/scripts/easyvpn-kick-client.sh"        "${SCRIPTS_TARGET_DIR}/easyvpn-kick-client.sh"
  echo "   Scripts instalados."
}

install_sudoers() {
  echo "-> Configurando sudoers en ${SUDOERS_FILE} ..."
  cat > "${SUDOERS_FILE}" <<'EOF'
asterisk ALL=(root) NOPASSWD: /usr/local/sbin/easyvpn-create-client.sh, /usr/local/sbin/easyvpn-revoke-client.sh, /usr/local/sbin/easyvpn-regenerate-profile.sh, /usr/local/sbin/easyvpn-status.sh, /usr/local/sbin/easyvpn-service.sh, /usr/local/sbin/easyvpn-kick-client.sh
EOF
  chmod 440 "${SUDOERS_FILE}"
  visudo -cf "${SUDOERS_FILE}" >/dev/null || {
    echo "ERROR: fallo al validar ${SUDOERS_FILE} con visudo" >&2
    exit 1
  }
  echo "   sudoers OK."
}

install_openvpn_server() {
  local script_dir="$1"

  echo
  echo "==============================="
  echo " Instalando servidor EasyVPN   "
  echo "==============================="

  # 1) Instalar paquetes
  echo "-> Instalando paquetes openvpn, easy-rsa y bc (Rocky)..."
  dnf install -y epel-release >/dev/null 2>&1 || true
  dnf install -y openvpn easy-rsa bc >/dev/null

  # 2) Directorios base
  echo "-> Creando estructura en ${EASYVPN_DIR} ..."
  mkdir -p "${EASYVPN_DIR}" "${EASYVPN_KEYS_DIR}" "${EASYVPN_GENERATED_DIR}" "${EASYVPN_CCD_DIR}"
  chown -R root:asterisk "${EASYVPN_DIR}"
  chmod 750 "${EASYVPN_DIR}" "${EASYVPN_GENERATED_DIR}" "${EASYVPN_CCD_DIR}"

  # 3) EasyRSA: inicializar PKI si no existe
  if [[ -d "${EASYVPN_DIR}/pki" ]]; then
    echo "   - PKI ya existe en ${EASYVPN_DIR}/pki, no se reinicializa."
  else
    echo "-> Inicializando EasyRSA en ${EASYVPN_DIR} ..."
    cp -r /usr/share/easy-rsa/3/* "${EASYVPN_DIR}/"
    cd "${EASYVPN_DIR}"

    export EASYRSA_BATCH=1
    ./easyrsa init-pki
    ./easyrsa build-ca nopass
    ./easyrsa build-server-full server nopass
    ./easyrsa gen-dh
    ./easyrsa gen-crl

    # ta.key para tls-auth
    openvpn --genkey --secret ta.key

    echo "   PKI creada (CA, server, dh, crl, ta.key)."
  fi

  # 4) Copiar llaves a keys/
  echo "-> Preparando keys en ${EASYVPN_KEYS_DIR} ..."
  cd "${EASYVPN_DIR}"
  cp -f "pki/ca.crt"                   "${EASYVPN_KEYS_DIR}/ca.crt"
  cp -f "pki/issued/server.crt"        "${EASYVPN_KEYS_DIR}/server.crt"
  cp -f "pki/private/server.key"       "${EASYVPN_KEYS_DIR}/server.key"
  cp -f "pki/dh.pem"                   "${EASYVPN_KEYS_DIR}/dh.pem"
  cp -f "pki/crl.pem"                  "${EASYVPN_KEYS_DIR}/crl.pem"
  cp -f "ta.key"                       "${EASYVPN_KEYS_DIR}/ta.key"

  chown root:asterisk "${EASYVPN_KEYS_DIR}"/*
  chmod 640 "${EASYVPN_KEYS_DIR}"/*

  # 5) client-template.ovpn (solo si no existe uno ya)
  if [[ -f "${EASYVPN_DIR}/client-template.ovpn" ]]; then
    echo "   - Ya existe client-template.ovpn en ${EASYVPN_DIR}, no se sobrescribe."
  else
    echo "-> Instalando plantilla client-template.ovpn ..."
    cp "${script_dir}/openvpn/client-template.ovpn" "${EASYVPN_DIR}/client-template.ovpn"
    chown root:asterisk "${EASYVPN_DIR}/client-template.ovpn"
    chmod 640 "${EASYVPN_DIR}/client-template.ovpn"
  fi

  # 6) Log status
  echo "-> Preparando status log en ${STATUS_LOG} ..."
  mkdir -p /var/log/openvpn
  touch /var/log/openvpn/easyvpn-status.log
  chown root:asterisk /var/log/openvpn/easyvpn-status.log
  chmod 640 /var/log/openvpn/easyvpn-status.log

  # 7) Crear server.conf si no existe
  mkdir -p "${SERVER_CONF_DIR}"
  if [[ -f "${SERVER_CONF}" ]]; then
    echo "   - Ya existe ${SERVER_CONF}, no se sobrescribe."
  else
    echo "-> Creando configuración de servidor en ${SERVER_CONF} ..."
    cat > "${SERVER_CONF}" <<EOF
port 1194
proto udp
dev tun

user nobody
group nobody

topology subnet
server 172.16.0.0 255.255.255.0

# Rango de VPN solo para teléfonos, ajusta según tus necesidades
ifconfig-pool-persist /var/log/openvpn/ipp-easyvpn.txt

# Rutas: aquí puedes empujar solo la IP del PBX si quieres aislar de la LAN
# push "route 192.168.1.6 255.255.255.255"

keepalive 10 120
persist-key
persist-tun

ca ${EASYVPN_KEYS_DIR}/ca.crt
cert ${EASYVPN_KEYS_DIR}/server.crt
key ${EASYVPN_KEYS_DIR}/server.key
dh ${EASYVPN_KEYS_DIR}/dh.pem

tls-auth ${EASYVPN_KEYS_DIR}/ta.key 0
key-direction 0

crl-verify ${EASYVPN_KEYS_DIR}/crl.pem

cipher AES-256-GCM
auth SHA256
ncp-ciphers AES-256-GCM:AES-128-GCM
remote-cert-tls client

status ${STATUS_LOG}
status-version 2
log-append /var/log/openvpn/easyvpn.log
management 127.0.0.1 7505
verb 3

client-config-dir ${EASYVPN_CCD_DIR}
explicit-exit-notify 1
EOF

    chmod 640 "${SERVER_CONF}"
  fi

  echo "-> Habilitando y arrancando servicio openvpn-server@easyvpn ..."
  systemctl enable --now openvpn-server@easyvpn.service

  echo
  echo "Servidor EasyVPN instalado y habilitado."
  echo "Ajusta ${SERVER_CONF} si necesitas rutas específicas (PBX, bloqueo LAN, etc.)."
}

main() {
  require_root

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WITH_SERVER="no"

  if [[ "${1-}" == "--with-server" ]]; then
    WITH_SERVER="yes"
  fi

  echo "Instalando módulo EasyVPN para Issabel 5"
  echo "Modo servidor: ${WITH_SERVER}"
  echo

  install_module "${SCRIPT_DIR}"
  install_scripts "${SCRIPT_DIR}"
  install_sudoers
  install_default_settings "${SCRIPT_DIR}"
  register_acl_and_menu

  if [[ "${WITH_SERVER}" == "yes" ]]; then
    install_openvpn_server "${SCRIPT_DIR}"
  else
    echo
    echo "NOTA: No se instaló ni configuró OpenVPN/EasyRSA."
    echo "      Si quieres que este script también prepare el servidor VPN,"
    echo "      ejecuta:  ./install.sh --with-server"
  fi

  echo
  echo "Instalación completada."
  echo "Reinicia Apache si es necesario:  systemctl restart httpd"
  echo "En Issabel: Security -> EasyVPN"
}

main "$@"

