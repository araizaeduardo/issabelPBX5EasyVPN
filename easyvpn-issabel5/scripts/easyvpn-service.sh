#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="openvpn-server@easyvpn.service"

case "${1-}" in
  start)
    systemctl start "$SERVICE_NAME"
    ;;
  stop)
    systemctl stop "$SERVICE_NAME"
    ;;
  restart)
    systemctl restart "$SERVICE_NAME"
    ;;
  status)
    # Solo queremos un resultado sencillo
    systemctl is-active "$SERVICE_NAME" || true
    ;;
  *)
    echo "Uso: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
 esac
