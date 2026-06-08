# Supported Versions and Interoperability

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This document states the toolchain and runtime versions the system is built and run against, and records the interoperability status of the external peers it speaks to. The version facts are confirmed against `rebar.config`. The interoperability section is an honest record: this repository carries **no tested-integration evidence** against any external peer, so the peer matrix is a record-keeping template, not a statement of verified interop.

Terms and abbreviations (HSS, UDR, MME, AMF, S6a, Diameter, SBI, Nudr, Erlang/OTP, rebar3, relx, MongoDB) are defined once in the [glossary](glossary.md) and are not redefined here.

> [!IMPORTANT]
> The version facts in §1 are normative for this release. The peer interoperability matrix in §3 is informative and explicitly **unverified**: no entry in it has been confirmed by an integration test in this repository.

## 1. Toolchain and runtime

The following are the supported build and run requirements for `udr` 0.1.0. They are facts read from `rebar.config`.

| Component | Version | Role | Confirmed in / notes |
| --- | --- | --- | --- |
| [Erlang/OTP](glossary.md) | 29 or later | Build and run | `minimum_otp_vsn` is `"29"` in `rebar.config`. Earlier OTP releases are not supported; the code uses OTP-29 features. See [install.md §1](install.md). |
| [rebar3](glossary.md) | Any recent release | Build, test, release | The build, test, and release tool. The project is a rebar3 umbrella. |
| [relx](glossary.md) | As bundled with rebar3 | Release assembly | Assembles release `udr` version `0.1.0` (the `relx` section of `rebar.config`). |
| [MongoDB](glossary.md) server | See note | The MongoDB backend only — **optional** | Not needed for the default [ETS](glossary.md) backend. The client driver is `comtihon/mongodb-erlang` tag `3.6.9` (a dependency in `rebar.config`). The driver tag, not a MongoDB **server** version, is what this repository pins; a compatible server version is a deployment choice and is **not yet verified** here. |
| Cowboy | `2.14.2` | HTTP server for the SBI and provisioning listeners | Pinned in `rebar.config`. Internal dependency; listed for completeness. |

> [!NOTE]
> The MongoDB **server** version is not pinned by this repository, and no server version has been verified against this release. The pinned value is the Erlang **client driver** version. An operator selecting the MongoDB backend `should` record the server version they validate against in the §3 matrix.

The system `shall` be built and run on Erlang/OTP 29 or later. The default [ETS](glossary.md) backend requires no external database; [MongoDB](glossary.md) `may` be selected in its place, in which case a compatible MongoDB server is an additional runtime requirement.

## 2. What "supported" means here

> [!NOTE]
> This section is informative.

"Supported" in §1 means the version the project's own build and test run against — what the code is written and compiled for. It does not, by itself, assert that the system has been run end to end against any particular external network function. That separate claim — interoperability with a real MME or 5G consumer — is the subject of §3, and it is currently unverified.

## 3. Peer interoperability matrix

This system speaks [S6a](glossary.md) to an [MME](glossary.md) and serves the [SBI](glossary.md) (Nudr-DR) to 5G consumers such as the [AMF](glossary.md). Whether it interoperates with any specific external implementation of those peers has **not** been tested in this repository.

> [!WARNING]
> No **external-peer** row below is a verified result: every third-party status is **Not yet verified**, and the named open-source peers (Open5GS, srsRAN) are **candidate targets** for an interoperability test campaign, not implementations this system has been shown to work with. The one exception is the project's own in-repo S6a client (the first row of §3.1), which verifies the HSS's S6a path in CI but is **not** a third-party interop result. Treat the candidate rows as a record-keeping template: an operator who runs an interoperability test `should` record the outcome, the peer version, and the date in the empty columns.

### 3.1 S6a peers (Diameter / `udr_diameter`)

| Peer (candidate) | Interface | Peer version tested | Status | Date verified | Notes |
| --- | --- | --- | --- | --- | --- |
| **udr S6a smoke client (in-repo)** | S6a (AIR/ULR) | this repository | **Verified (CI)** | 2026-06-08 | The project's own Diameter client ([`demos/s6a-smoke`](../../demos/s6a-smoke/)), run by `.github/workflows/demo-s6a.yml`: AIR → AIA `2001` with the requested vectors, ULR → ULA `2001`. Confirms the HSS S6a path; **not** a third-party interop result. |
| Open5GS MME | S6a (AIR/ULR/PUR/CLR) | — | Not yet verified | — | Candidate target for an interop campaign. Not tested here. |
| srsRAN (with EPC/MME) | S6a | — | Not yet verified | — | Candidate target. Not tested here. |
| _(operator's MME)_ | S6a | — | Not yet verified | — | Record the operator's own MME implementation and result. |

### 3.2 SBI / Nudr-DR consumers (`udr_sbi`)

| Consumer (candidate) | Interface | Consumer version tested | Status | Date verified | Notes |
| --- | --- | --- | --- | --- | --- |
| Open5GS AMF/UDM | SBI / Nudr-DR (`/nudr-dr/v1/...`) | — | Not yet verified | — | Candidate target. The exposed resources are a Nudr-**flavored** subset; full Nudr conformance is not claimed. |
| _(operator's AMF/UDM)_ | SBI / Nudr-DR | — | Not yet verified | — | Record the operator's own consumer and result. |

> [!NOTE]
> The SBI is described in the manual as a Nudr-**flavored** interface: it exposes a subset of resources shaped after Nudr-DR, not a conformance-tested implementation of the full 3GPP Nudr service. The exact resources and status codes the code returns are the authoritative contract; see the [SBI interface reference](interfaces/sbi.md). Do not infer Nudr conformance from this document.

## 4. Running an interoperability test (where to start)

When an interoperability campaign is run, each result `should` be recorded in the §3 matrix with the peer version and the date. The procedures that exercise the interfaces against a real peer are:

- [`RUN-S6A-PEER-001`](operations/s6a-peer.md) — connect and verify an MME over S6a (CER/CEA, then an AIR/ULR exchange).
- [interfaces/sbi.md](interfaces/sbi.md) — the SBI resources and status codes a consumer will exercise.

An observable S6a interop result is, for example: a peer's [CER](glossary.md) is answered with a [CEA](glossary.md) carrying the configured `Origin-Host`, and an `AIR` for a provisioned [IMSI](glossary.md) returns an `AIA` with `Result-Code` `2001`. Recording that outcome — with the peer's name, version, and the date — is what turns a row in §3 from "Not yet verified" into a real result.

## 5. Related documents

- [install.md](install.md) — the prerequisites and build, where the OTP and rebar3 requirements first appear.
- [configuration/data-store.md](configuration/data-store.md) — selecting and configuring the MongoDB backend.
- [operations/s6a-peer.md](operations/s6a-peer.md) — connecting and verifying an MME, the basis of an S6a interop test.
- [interfaces/s6a.md](interfaces/s6a.md) and [interfaces/sbi.md](interfaces/sbi.md) — the interface contracts a peer is tested against.
