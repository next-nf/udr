# Demos

Ready-to-use demonstrations of the HSS/UDR. Each demo lives in its own
subdirectory with a `run.sh` and a `README.md` that explains what it proves; the
CI-gated ones also ship a `docker-compose.yml`.

| Demo | What it proves | Runs in |
| --- | --- | --- |
| [`s6a-smoke/`](s6a-smoke/) | The project's own Diameter client provisions a subscriber and gets authentication vectors (AIR) and a location update (ULR) from the HSS over S6a. | Locally and in CI |
| [`open5gs-s6a/`](open5gs-s6a/) | A real **Open5GS MME** (freeDiameter) establishes the S6a Diameter peer with the HSS (CER/CEA) over TCP. | Locally and in CI |
| [`srsran-attach/`](srsran-attach/) | A real **srsRAN UE** attaches through an Open5GS MME, driving the full S6a **AIR/ULR** exchange end to end. The demo that found and verified the fix for the S6a AIR crash. | Locally (manual — needs the host `sctp` module) |

The interoperability outcomes these demos establish are recorded in the project's
`docs/manual/compatibility.md`. A full data-plane attach (UE gets an IP) is not
covered here — it needs the EPC user plane and a privileged host; see
[`srsran-attach/README.md`](srsran-attach/README.md).

## Conventions

- **Diameter transport is TCP.** The HSS S6a listener binds `{tcp, …, 3868}`
  (see `config/docker.sys.config`), so every Diameter peer in a demo is
  configured for TCP, not SCTP.
- **Demo credentials are public test vectors.** The `Ki`/`OPc` used by
  [`provision.sh`](provision.sh) are well-known MILENAGE test values. They are
  for demonstration only and `shall not` be used as operational credentials.
- **Each demo is hermetic.** `run.sh` builds the images, runs the check, and
  removes the containers and volumes on exit, so a demo leaves nothing behind.

## Shared helpers

- [`provision.sh`](provision.sh) `<host> <port> <imsi>` — create a subscriber via
  the provisioning API and assert `201 Created`. Used by the demos to seed a
  subscriber before signalling.
