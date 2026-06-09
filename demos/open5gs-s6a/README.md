# Open5GS MME ↔ HSS S6a interop demo (D2a)

A real **[Open5GS](https://open5gs.org/) MME** peering with our HSS over the
**S6a Diameter** interface. Unlike the [`s6a-smoke`](../s6a-smoke/) demo — which
uses the project's own OTP Diameter client — this exercises our HSS against a
*third-party* Diameter stack (Open5GS's **freeDiameter**), which is what catches
real base-protocol and AVP-encoding differences.

## What it proves (and what it does not, yet)

- **Proves (D2a):** the Open5GS MME establishes the S6a Diameter peer connection
  to our HSS — the **CER/CEA** capability exchange completes over TCP. The demo
  asserts the MME logs `CONNECTED TO 'hss.epc.mnc001.mcc001.3gppnetwork.org'`.
- **Not yet (D2b):** an actual subscriber **attach** (which makes the MME send
  `AIR`/`ULR`) needs an S1AP/NAS driver (an eNB/UE simulator) over SCTP. That is
  the next step and is tracked separately.

## Requirements

- Docker with the Compose plugin (or run the equivalent with podman — see Notes).
- The **`sctp` kernel module** loaded on the host: the Open5GS MME opens an S1AP
  SCTP socket at startup. Load it with `sudo modprobe sctp`.

## Run it

```sh
./run.sh
```

`run.sh` starts the HSS and the Open5GS MME, waits for the Diameter peering, and
prints the confirming log line. Expected:

```
==> PASS: the Open5GS MME peered with our HSS over S6a Diameter:
... [diam] INFO: CONNECTED TO 'hss.epc.mnc001.mcc001.3gppnetwork.org' (TCP,soc#19)
```

## How it is wired

- **HSS:** the released `ghcr.io/next-nf/udr:latest` image — default ETS backend,
  S6a listener on `3868/TCP` (`config/docker.sys.config`).
- **MME:** `openverso/open5gs` (Open5GS v2.4.0). Only its freeDiameter config is
  customized ([`mme/mme.conf`](mme/mme.conf)): the `ConnectPeer` points at our HSS
  over TCP with `No_TLS`/`No_SCTP`, and the peer identity
  `hss.epc.mnc001.mcc001.3gppnetwork.org` and realm match our HSS. The MME's own
  identity stays `mme.openverso` so it matches the cert shipped in the image.

## Notes

- **Transport is TCP.** Our HSS S6a listener is TCP, so the MME's `ConnectPeer`
  forces TCP (`No_SCTP`) with `No_TLS`. SCTP is needed only for the MME's *S1AP*
  socket, not for S6a here.
- **Local podman:** the demo's `run.sh` uses `docker compose`. With podman, the
  bundled compose provider may be too old for the Compose Spec; run the steps with
  `podman` directly, or `podman-compose`, instead.
- **Image pinning:** `openverso/open5gs:latest` is Open5GS v2.4.0 at the time of
  writing; pin a digest for full reproducibility.

This demo's result is recorded in
[`docs/manual/compatibility.md`](../../docs/manual/compatibility.md).
