#!/usr/bin/env sh
# Provision one subscriber via the HSS provisioning API and assert 201 Created.
#
# Usage: provision.sh [HOST] [PORT] [IMSI]
#   HOST  provisioning API host           (default 127.0.0.1)
#   PORT  provisioning API port           (default 8090)
#   IMSI  subscriber IMSI                  (default 001010000000001)
#
# The Ki/OPc below are well-known public MILENAGE test values (3GPP TS 35.207
# style). They are for demonstration ONLY and must never be used as operational
# credentials.
set -eu

HOST="${1:-127.0.0.1}"
PORT="${2:-8090}"
IMSI="${3:-001010000000001}"

BODY='{
  "auth": {
    "ki":  "465b5ce8b199b49faa5f0a2ee238a6bc",
    "opc": "cd63cb71954a9f4e48a5994e37a02baf",
    "amf": "b9b9",
    "sqn": 0
  },
  "profile": { "subscriber-status": 0, "msisdn": "11112345678" }
}'

out=$(mktemp)
code=$(curl -s -o "$out" -w '%{http_code}' \
  -X PUT -H 'Content-Type: application/json' \
  --data "$BODY" \
  "http://${HOST}:${PORT}/provision/v1/subscribers/${IMSI}" || true)

if [ "$code" != "201" ]; then
  echo "provision FAILED for ${IMSI}: HTTP ${code}"
  cat "$out" 2>/dev/null || true
  rm -f "$out"
  exit 1
fi

echo "provisioned ${IMSI} (HTTP 201): $(cat "$out")"
rm -f "$out"
