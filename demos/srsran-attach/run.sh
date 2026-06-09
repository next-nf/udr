#!/usr/bin/env sh
# Manual interop demo (D2b): a real srsRAN UE attaches through an Open5GS MME to
# our HSS, driving the S6a AIR/ULR exchange end to end over a real third-party
# Diameter stack. This is the demo that surfaced — and then verified the fix for —
# the S6a AIR decode crash (PR #12).
#
# This is NOT a CI gate (see README.md). It needs:
#   - the host `sctp` kernel module:  sudo modprobe sctp
#   - podman (or `ENGINE=docker`), and /dev/net/tun for the UE
# The radio link is emulated over ZeroMQ (no SDR). The user plane (UE gets an IP /
# internet) is out of scope here — that needs the EPC data nodes (SGW/UPF), which
# rootless containers can't provide. See README.md.
set -eu
cd "$(dirname "$0")"

ENGINE=${ENGINE:-podman}
NET=srs-attach
HSS_IMG=${HSS_IMG:-ghcr.io/next-nf/udr:latest}
MME_IMG=${MME_IMG:-docker.io/openverso/open5gs:latest}
RAN_IMG=${RAN_IMG:-ghcr.io/next-nf/srsran-4g:release_25_10}
IMSI=208960100000001

grep -qi sctp /proc/net/protocols 2>/dev/null || { echo "SCTP not loaded — run: sudo modprobe sctp"; exit 1; }

cleanup() { $ENGINE rm -f hss mme enb ue >/dev/null 2>&1 || true; $ENGINE network rm $NET >/dev/null 2>&1 || true; }
trap cleanup EXIT
$ENGINE network rm $NET >/dev/null 2>&1 || true
$ENGINE network create --subnet 192.168.61.0/24 $NET >/dev/null

echo "==> HSS (.2) — realm 'openverso' to match the MME (S6a routing is realm-based)"
SYSCFG=$($ENGINE run --rm --entrypoint sh "$HSS_IMG" -c 'ls /opt/udr/releases/*/sys.config 2>/dev/null | head -1')
[ -n "$SYSCFG" ] || { echo "could not locate the release sys.config in $HSS_IMG"; exit 1; }
$ENGINE run -d --name hss --network $NET --ip 192.168.61.2 \
  -v "$PWD/hss.sys.config:$SYSCFG:ro,Z" "$HSS_IMG" >/dev/null

echo "==> provisioning subscriber $IMSI"
i=0; until $ENGINE run --rm --network $NET docker.io/curlimages/curl:latest -s -o /dev/null -w '%{http_code}' \
  http://192.168.61.2:8090/provision/v1/subscribers/x 2>/dev/null | grep -qE '20|40'; do
  i=$((i + 1)); [ $i -ge 25 ] && { echo "HSS not ready"; exit 1; }; sleep 1; done
$ENGINE run --rm --network $NET docker.io/curlimages/curl:latest -s -o /dev/null -w '    provision HTTP %{http_code}\n' \
  -X PUT -H 'content-type: application/json' \
  --data '{"auth":{"ki":"fec86ba6eb707ed08905757b1bb44b8f","opc":"c42449363bbad02b66d16bc975d77cc1","amf":"8000","sqn":0},"profile":{}}' \
  http://192.168.61.2:8090/provision/v1/subscribers/$IMSI

echo "==> MME (.3) — Open5GS, S6a to our HSS; sgwc/smf stubbed (no data plane here)"
$ENGINE run -d --name mme --network $NET --ip 192.168.61.3 --add-host sgwc:127.0.0.1 --add-host smf:127.0.0.1 \
  -v "$PWD/mme/mme.conf:/opt/open5gs/etc/freeDiameter/mme.conf:ro,Z" \
  -v "$PWD/mme/mme.yaml:/opt/open5gs/etc/open5gs/mme.yaml:ro,Z" \
  "$MME_IMG" /opt/open5gs/bin/open5gs-mmed -c /opt/open5gs/etc/open5gs/mme.yaml >/dev/null
i=0; until $ENGINE logs mme 2>&1 | grep -q "CONNECTED TO 'hss.openverso'"; do i=$((i + 1)); [ $i -ge 20 ] && break; sleep 1; done

echo "==> srsRAN eNB (.20)"
$ENGINE run -d --name enb --network $NET --ip 192.168.61.20 \
  -v "$PWD/enb.conf:/cfg/enb.conf:ro,Z" -v "$PWD/sib.conf:/cfg/sib.conf:ro,Z" \
  "$RAN_IMG" srsenb /cfg/enb.conf >/dev/null
i=0; until $ENGINE logs enb 2>&1 | grep -qi "eNodeB started"; do i=$((i + 1)); [ $i -ge 10 ] && break; sleep 1; done

echo "==> srsRAN UE (.30) — attaching..."
hcrash=$($ENGINE logs hss 2>&1 | grep -c 'ERROR REPORT' || true)
$ENGINE run -d --name ue --network $NET --ip 192.168.61.30 --cap-add=NET_ADMIN --device /dev/net/tun \
  -v "$PWD/ue.conf:/cfg/ue.conf:ro,Z" "$RAN_IMG" srsue /cfg/ue.conf >/dev/null
i=0; until $ENGINE logs mme 2>&1 | grep -qE "Message-Type\[170\]|emm-sm.c:1099"; do
  i=$((i + 1)); [ $i -ge 30 ] && break; sleep 2; done

echo ""
echo "==> RESULT"
crash_now=$($ENGINE logs hss 2>&1 | grep -c 'ERROR REPORT' || true)
echo "    HSS crashes during attach: $((crash_now - hcrash))   (expect 0 with the PR #12 fix)"
if $ENGINE logs mme 2>&1 | grep -qE "Message-Type\[170\]"; then
  echo "    MME reached GTP Create Session  =>  AIR->AIA and ULR->ULA SUCCEEDED over S6a."
  echo "    The attach then stops at session creation (no SGW/UPF = the data plane, out of scope)."
  echo "    PASS: a real srsRAN UE attach drove the full S6a control plane through our HSS."
else
  echo "    Attach did not reach session creation. Inspect: $ENGINE logs mme | grep -i emm"
fi
echo ""
echo "Tearing down. Set KEEP=1 to leave the containers up for inspection."
[ "${KEEP:-0}" = "1" ] && trap - EXIT || true
