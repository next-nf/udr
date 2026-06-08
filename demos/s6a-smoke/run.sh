#!/usr/bin/env sh
# S6a smoke demo. Builds and starts the HSS, provisions a subscriber, then runs a
# Diameter MME client that sends AIR + ULR and asserts the answers. Exits 0 only
# if the client reports PASS. Leaves nothing behind.
set -eu
cd "$(dirname "$0")"

PROV_HOST=127.0.0.1
PROV_PORT=8090
IMSI=001010000000001

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> Building and starting the HSS"
docker compose up -d --build hss

echo "==> Waiting for the provisioning API on ${PROV_HOST}:${PROV_PORT}"
i=0
while :; do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    "http://${PROV_HOST}:${PROV_PORT}/provision/v1/subscribers/000000000000000" || true)
  [ "$code" != "000" ] && break
  i=$((i + 1))
  if [ "$i" -ge 90 ]; then
    echo "HSS did not become ready in time"
    docker compose logs hss || true
    exit 1
  fi
  sleep 1
done
echo "    HSS is up (provisioning API returned HTTP ${code})"

echo "==> Provisioning subscriber ${IMSI}"
../provision.sh "${PROV_HOST}" "${PROV_PORT}" "${IMSI}"

echo "==> Running the S6a MME client (AIR + ULR)"
docker compose build mme
docker compose run --rm mme

echo "==> Demo passed: the HSS authenticated and located the subscriber over S6a"
