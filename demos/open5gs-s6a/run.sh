#!/usr/bin/env sh
# D2a: Open5GS MME <-> udr HSS S6a Diameter peering.
#
# Brings up our HSS and a real Open5GS MME (freeDiameter) configured to peer with
# it over S6a/TCP, and asserts the MME establishes the Diameter connection (the
# CER/CEA capability exchange succeeds). This proves a third-party Diameter stack
# interoperates with our HSS at the S6a base-protocol level.
#
# Requires the host sctp module (the MME opens an S1AP SCTP socket at startup):
#   sudo modprobe sctp
set -eu
cd "$(dirname "$0")"

PEER="hss.epc.mnc001.mcc001.3gppnetwork.org"

cleanup() { docker compose down -v --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

if ! grep -qi sctp /proc/net/protocols 2>/dev/null; then
  echo "WARNING: SCTP is not loaded; the Open5GS MME needs it for its S1AP socket."
  echo "         Load it with:  sudo modprobe sctp"
fi

echo "==> Starting the HSS and the Open5GS MME"
docker compose up -d

# The MME image sleeps ~10s before starting the daemon (a DNS-readiness workaround),
# so give it a head start before polling its logs.
sleep 12

echo "==> Waiting for the MME (freeDiameter) to peer with the HSS over S6a"
i=0
until docker compose logs mme 2>/dev/null | grep -q "CONNECTED TO '${PEER}'"; do
  i=$((i + 1))
  if [ "$i" -ge 90 ]; then
    echo "FAILED: the MME did not establish a Diameter peer with the HSS"
    echo "---- mme logs ----"; docker compose logs mme | tail -40
    exit 1
  fi
  sleep 1
done

echo "==> PASS: the Open5GS MME peered with our HSS over S6a Diameter:"
docker compose logs mme 2>/dev/null | grep "CONNECTED TO '${PEER}'" | tail -1
