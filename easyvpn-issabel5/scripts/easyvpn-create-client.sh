#!/usr/bin/env bash
set -euo pipefail

EASYRSA_DIR="/etc/openvpn/easyvpn"
KEYS_DIR="/etc/openvpn/easyvpn/keys"
GEN_DIR="/etc/openvpn/easyvpn/generated"
SERVER_PUBLIC_IP="pbx.paseotravel.com"   # <-- CAMBIA ESTO
SERVER_PORT="2004"
PROTO="udp"

if [[ $# -lt 1 ]]; then
  echo "Uso: $0 <nombre_cliente>"
  exit 1
fi

CLIENT="$1"

cd "$EASYRSA_DIR"

# Modo no interactivo para EasyRSA
export EASYRSA_BATCH=1
export EASYRSA_ALGO="rsa"
export EASYRSA_KEY_SIZE=4096
export EASYRSA_DIGEST="sha256"

# Generar certificado cliente si no existe
if [[ ! -f "pki/issued/${CLIENT}.crt" ]]; then
  ./easyrsa build-client-full "$CLIENT" nopass
fi

# Paths
CA="$EASYRSA_DIR/pki/ca.crt"
CRT="$EASYRSA_DIR/pki/issued/${CLIENT}.crt"
KEY="$EASYRSA_DIR/pki/private/${CLIENT}.key"

OUT_OVPN="${GEN_DIR}/${CLIENT}.ovpn"
OUT_TAR="${GEN_DIR}/${CLIENT}-grandstream.tar"

mkdir -p "$GEN_DIR"

cat > "$OUT_OVPN" <<EOF
client
dev tun
proto ${PROTO}
remote ${SERVER_PUBLIC_IP} ${SERVER_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-GCM
remote-cert-tls server
verb 3
<ca>
$(cat "$CA")
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$p' "$CRT")
</cert>
<key>
$(cat "$KEY")
</key>
EOF

# Paquete tar para Grandstream
TMPDIR=$(mktemp -d)
cp "$CA" "$TMPDIR/ca.crt"
cp "$CRT" "$TMPDIR/client.crt"
cp "$KEY" "$TMPDIR/client.key"
tar -czf "$OUT_TAR" -C "$TMPDIR" .
rm -rf "$TMPDIR"

echo "Generado:"
echo " - $OUT_OVPN"
echo " - $OUT_TAR (para Grandstream)"

