#!/usr/bin/env bash
STATUS_FILE="/var/log/openvpn/easyvpn-status.log"

if [[ ! -f "$STATUS_FILE" ]]; then
  echo "STATUS_FILE_NOT_FOUND"
  exit 1
fi

awk '
/^Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since/ {header=1; next}
header && NF {
  if ($1 == "ROUTING" || $1 == "GLOBAL") exit
  print $1","$2","$3","$4","$5,$6,$7,$8
}
' "$STATUS_FILE"

