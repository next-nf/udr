# Demos

Ready-to-use, self-contained demonstrations of the HSS/UDR. Each demo lives in
its own subdirectory with a `docker-compose.yml`, a `run.sh` that brings the
stack up, exercises it, asserts the outcome, and tears it down, and a `README.md`
that explains what it proves.

| Demo | What it proves | Runs in |
| --- | --- | --- |
| [`s6a-smoke/`](s6a-smoke/) | A Diameter MME client provisions a subscriber and gets authentication vectors and a location update from the HSS over S6a. | Locally and in CI (GitHub Actions) |

More demos (Open5GS MME interop, full RAN) are planned; see the project's
`docs/manual/compatibility.md` for the interoperability record each demo feeds.

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
