# srsRAN attach demo — full S6a control plane (D2b)

A **manual, local** interop demo: a real **srsRAN UE** attaches through a real
**Open5GS MME** to **our HSS**, driving the **S6a `AIR`/`ULR` exchange** end to end
— the way an actual phone would. Unlike [`s6a-smoke`](../s6a-smoke/) (our own OTP
Diameter client) and [`open5gs-s6a`](../open5gs-s6a/) (Diameter peering only), this
exercises the HSS against a real RAN + a real third-party Diameter stack
(Open5GS's freeDiameter) under a genuine LTE attach.

> [!IMPORTANT]
> This is **not** a CI gate. It needs the host `sctp` kernel module, `/dev/net/tun`,
> and emulates the radio over ZeroMQ. The **user plane is out of scope** — the UE
> does not get an IP / internet here, because that needs the EPC data nodes
> (SGW-C/U, SMF, UPF) and a kernel user plane that rootless containers can't
> provide. The control plane (authentication + location update) is what this proves.

## Why it exists

This demo found a real bug. The first time a real Open5GS `AIR` reached our HSS, the
S6a request process **crashed** (it returned `{answer_message, 5005}`, which OTP's
`diameter` rejects) — a path our synthetic test client never hit. That was fixed in
**PR #12** (`fix/s6a-air-decode-error-rfc6733`: answer malformed requests per
RFC 6733, and accept the extra AVPs Open5GS puts in the `ULR`). Re-running this demo
against the fixed HSS, the attach now completes the full S6a control plane.

## What it proves

With the PR #12 fix, a real UE attach drives, with **no HSS crash**:

- `AIR` → `AIA` — the HSS returns EPS authentication vectors; the UE authenticates.
- `ULR` → `ULA` — the HSS returns subscription data; the MME location-updates.

The attach then stops at GTP **Create Session** (the MME has no SGW here) — that is
the data plane (D3), not the HSS. Reaching Create Session is itself the proof that
`AIR` and `ULR` both succeeded.

## Topology

```
srsRAN UE ──ZeroMQ──▶ srsRAN eNB ──S1AP/SCTP──▶ Open5GS MME ──S6a/Diameter(TCP)──▶ our HSS
 (USIM)                (PLMN 208/96)              (realm openverso)                 (realm openverso)
```

All on a static-IP network `192.168.61.0/24`: hss `.2`, mme `.3`, enb `.20`, ue `.30`.

## Requirements

- `podman` (or `ENGINE=docker ./run.sh`), plus `/dev/net/tun`.
- The host **`sctp`** module loaded — the MME's S1AP socket and the eNB need it:
  `sudo modprobe sctp`.
- Network access to pull: `ghcr.io/next-nf/udr` (our HSS, with the PR #12 fix),
  `ghcr.io/next-nf/srsran-4g:release_25_10` (srsRAN eNB+UE, ZeroMQ), and
  `docker.io/openverso/open5gs` (the MME).

## Run it

```sh
sudo modprobe sctp
./run.sh
```

Expected tail:

```
==> RESULT
    HSS crashes during attach: 0   (expect 0 with the PR #12 fix)
    MME reached GTP Create Session  =>  AIR->AIA and ULR->ULA SUCCEEDED over S6a.
    PASS: a real srsRAN UE attach drove the full S6a control plane through our HSS.
```

## How it is wired (the non-obvious bits)

- **Realm.** The Open5GS MME defaults to realm `openverso`, and S6a request routing
  is realm-based — so the HSS is put in the **same realm** via
  [`hss.sys.config`](hss.sys.config) (`origin_host = hss.openverso`,
  `origin_realm = openverso`), mounted over the release's `sys.config`. The MME's
  freeDiameter [`mme/mme.conf`](mme/mme.conf) connects to it over **TCP / `No_TLS`**
  (our S6a listener is TCP).
- **PLMN / TAC.** The MME ([`mme/mme.yaml`](mme/mme.yaml)) serves PLMN **208/96**,
  TAC **7**, to match srsRAN's defaults (srsRAN's TAC lives in `rr.conf`, not
  `enb.conf`).
- **Radio.** [`enb.conf`](enb.conf)/[`ue.conf`](ue.conf) use srsRAN's **ZeroMQ** RF
  (`base_srate=11.52e6`, 6 PRB); [`sib.conf`](sib.conf) sets `prach_freq_offset=0`
  so PRACH fits in 6 PRB.
- **Subscriber.** IMSI `208960100000001`, Ki/OPc = the public OAI test vectors,
  provisioned via the provisioning API.

## Why not CI

It depends on a host kernel module (`sctp`), `/dev/net/tun`, image pulls, and a
timing-sensitive ZeroMQ radio sync + LTE attach — too heavy and flaky for a gate.
The CI-gated S6a checks are [`s6a-smoke`](../s6a-smoke/) and
[`open5gs-s6a`](../open5gs-s6a/). This demo is the manual, full-stack confirmation.

## Beyond this (D3)

A fully green attach — UE gets an IP and reaches the internet — needs the EPC user
plane (MongoDB + PCRF + SMF + UPF, with TUN/GTP-U/NAT). That requires root
(privileged) networking, so its natural home is a real VM, ideally adapting a
ready reference such as [`herlesupreeth/docker_open5gs`](https://github.com/herlesupreeth/docker_open5gs)
with our HSS swapped in.
