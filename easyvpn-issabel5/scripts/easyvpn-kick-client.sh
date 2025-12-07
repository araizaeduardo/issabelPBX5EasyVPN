#!/usr/bin/env bash
set -euo pipefail

CID="${1-}"

if [[ -z "${CID}" ]]; then
  echo "Uso: $0 <client_id>" >&2
  exit 1
fi

MGMT_HOST="127.0.0.1"
MGMT_PORT="7505"

{
  echo "kill ${CID}"
  sleep 1
  echo "quit"
} | nc "${MGMT_HOST}" "${MGMT_PORT}" || {
  echo "Error al comunicar con la interfaz de management" >&2
  exit 1
}
