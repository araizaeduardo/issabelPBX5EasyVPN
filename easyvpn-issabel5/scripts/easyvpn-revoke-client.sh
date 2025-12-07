#!/usr/bin/env bash
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easyvpn"
KEYS_DIR="/etc/openvpn/easyvpn/keys"

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 <CN_cliente>" >&2
  exit 1
fi

CLIENT="$1"

cd "$EASYRSA_DIR"

export EASYRSA_BATCH=1
export EASYRSA_ALGO="rsa"
export EASYRSA_KEY_SIZE=4096
export EASYRSA_DIGEST="sha256"

echo "Revocando certificado de $CLIENT ..."
./easyrsa revoke "$CLIENT"

echo "Regenerando CRL ..."
./easyrsa gen-crl

# --- Reparar permisos que EasyRSA siempre rompe ---
chown root:asterisk "$EASYRSA_DIR/pki/index.txt"
chmod 640 "$EASYRSA_DIR/pki/index.txt"

chown root:asterisk "$EASYRSA_DIR/pki/index.txt.attr" "$EASYRSA_DIR/pki/index.txt.attr.old" 2>/dev/null
chmod 640 "$EASYRSA_DIR/pki/index.txt.attr" "$EASYRSA_DIR/pki/index.txt.attr.old" 2>/dev/null

install -o root -g asterisk -m 640 "$EASYRSA_DIR/pki/crl.pem" "$KEYS_DIR/crl.pem"

echo "OK: certificado de $CLIENT revocado."

