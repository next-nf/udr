# S6a smoke demo

A self-contained demonstration that the HSS authenticates and locates a
subscriber over the **S6a Diameter** interface — the interface an MME uses
against an EPC HSS.

It runs two containers:

- **`hss`** — the HSS, built from the repository's release image, with the
  default in-memory ETS backend (no database needed).
- **`mme`** — a minimal Diameter MME client ([`mme/smoke_mme.erl`](mme/smoke_mme.erl),
  adapted from the project's own test MME) that connects over TCP, sends an
  **AIR** and a **ULR**, and asserts the answers.

## What it proves

1. A subscriber provisioned through the provisioning API is reachable by S6a.
2. An **AIR** returns an **AIA** with `Result-Code 2001` and the requested number
   of EPS authentication vectors (MILENAGE).
3. A **ULR** returns a **ULA** with `Result-Code 2001`.

If any step fails, the client prints `RESULT: FAIL` and exits non-zero, and the
demo fails.

## Run it

Requirements: Docker with the Compose plugin.

```sh
./run.sh
```

`run.sh` builds the images, starts the HSS, provisions IMSI `001010000000001`
with public MILENAGE test credentials, runs the MME client, and tears everything
down. Expected tail of a successful run:

```
==> Running the S6a MME client (AIR + ULR)
S6a smoke client -> hss:3868  (IMSI 001010000000001, 2 vectors)
  AIR -> AIA  Result-Code=2001  vectors=2  OK
  ULR -> ULA  Result-Code=2001  OK
RESULT: PASS
==> Demo passed: the HSS authenticated and located the subscriber over S6a
```

## How it maps to the manual

- The S6a contract exercised here is documented in
  [`docs/manual/interfaces/s6a.md`](../../docs/manual/interfaces/s6a.md).
- The provisioning request is documented in
  [`docs/manual/interfaces/provisioning.md`](../../docs/manual/interfaces/provisioning.md).
- This demo runs in CI (`.github/workflows/demo-s6a.yml`); its result is the
  first verified row in [`docs/manual/compatibility.md`](../../docs/manual/compatibility.md).

## Notes

- **Transport is TCP.** The HSS S6a listener is `{tcp, …, 3868}`, so the client
  connects over TCP (not SCTP).
- **Credentials are public test vectors**, for demonstration only.
