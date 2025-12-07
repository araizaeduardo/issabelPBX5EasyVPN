#!/usr/bin/env bash
set -euo pipefail

EASYVPN_DIR="/etc/openvpn/easyvpn"
GENERATED_DIR="$EASYVPN_DIR/generated"

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 <CN_cliente>" >&2
  exit 1
fi

CN="$1"

CRT="$EASYVPN_DIR/pki/issued/$CN.crt"
KEY="$EASYVPN_DIR/pki/private/$CN.key"
CA="$EASYVPN_DIR/pki/ca.crt"
TA="$EASYVPN_DIR/ta.key"
TEMPLATE="$EASYVPN_DIR/client-template.ovpn"

OVPN_OUT="$GENERATED_DIR/$CN.ovpn"
TAR_OUT="$GENERATED_DIR/$CN-grandstream.tar"

# Verificaciones
[[ -f "$CRT" ]] || { echo "Error: No existe $CRT"; exit 1; }
[[ -f "$KEY" ]] || { echo "Error: No existe $KEY"; exit 1; }
[[ -f "$TEMPLATE" ]] || { echo "Error: No existe plantilla client-template.ovpn"; exit 1; }

# Crear .ovpn inline
cp "$TEMPLATE" "$OVPN_OUT"

{
  echo "<ca>"
  cat "$CA"
  echo "</ca>"
  echo "<cert>"
  sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$CRT"
  echo "</cert>"
  echo "<key>"
  cat "$KEY"
  echo "</key>"
  if [[ -f "$TA" ]]; then
    echo "<tls-auth>"
    cat "$TA"
    echo "</tls-auth>"
  fi
} >> "$OVPN_OUT"

# Crear paquete Grandstream
tar -C "$EASYVPN_DIR/pki" -cf "$TAR_OUT" \
  "issued/$CN.crt" \
  "private/$CN.key" \
  "ca.crt" \
  "../ta.key" \
  2>/dev/null || true

chmod 640 "$OVPN_OUT" "$TAR_OUT"
chown root:asterisk "$OVPN_OUT" "$TAR_OUT"

echo "Perfil regenerado para $CN"

