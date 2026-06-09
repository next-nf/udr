# udr — a 3GPP HSS + UDR/UDM in Erlang/OTP

[![CI](https://github.com/next-nf/udr/actions/workflows/ci.yml/badge.svg)](https://github.com/next-nf/udr/actions/workflows/ci.yml)
[![S6a smoke](https://github.com/next-nf/udr/actions/workflows/demo-s6a.yml/badge.svg)](https://github.com/next-nf/udr/actions/workflows/demo-s6a.yml)
[![Open5GS interop](https://github.com/next-nf/udr/actions/workflows/demo-open5gs.yml/badge.svg)](https://github.com/next-nf/udr/actions/workflows/demo-open5gs.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

A converged **Home Subscriber Server (HSS)** and **Unified Data Repository / Unified Data Management (UDR/UDM)** for 4G/LTE and 5G core networks, written in Erlang/OTP.

It speaks the **S6a Diameter** interface that an MME expects from an EPC HSS, and exposes a **5G Service-Based Interface (Nudr-DR)** for subscriber data — backed by a pluggable document store, clustered for per-subscriber consistency, and instrumented with OpenTelemetry out of the box.

> [!NOTE]
> **Why Erlang?** Erlang was created at Ericsson to run telephone switches — soft real-time, massively concurrent, and built to stay up through faults and upgrades. A subscriber database on the signalling path is exactly that workload: many small concurrent transactions, strict latency, and no acceptable downtime. This project puts a modern 3GPP core network function back on the runtime that was designed for telecom in the first place.

> [!WARNING]
> **Status:** early (v0.1.0). The interfaces below work end to end; the surface is deliberately small and growing. Not yet a drop-in for a production network.

---

## Features

- **S6a HSS** — `AIR` (Authentication-Information), `ULR` (Update-Location), `PUR` (Purge-UE), with HSS-initiated `CLR` (Cancel-Location).
- **5G SBI (Nudr-DR)** — Nudr-flavoured `subscription-data` resource: authentication subscription, access-and-mobility data, and AMF registration context.
- **MILENAGE authentication** — full f1–f5 / f1\* / f5\* / OPc per 3GPP TS 35.205/206, behind a pluggable algorithm behaviour so other algorithm sets can be added.
- **Pluggable data store** — in-memory ETS backend by default (zero external dependencies); MongoDB backend available by configuration.
- **Cluster-aware** — per-IMSI session locking across nodes via [`syn`](https://hex.pm/packages/syn), so concurrent signalling for one subscriber serialises correctly.
- **Admin provisioning API** — HTTP API to create, read, and delete subscribers by IMSI.
- **Observability** — OpenTelemetry traces and metrics (OTLP exporter) wired through the Diameter and HTTP paths.

## Interoperability

`udr` is tested against the dominant open-source mobile-core stack — not just its own unit tests:

- An **Open5GS MME** (freeDiameter) establishes the S6a Diameter peer (CER/CEA) with `udr` over TCP — **gated in CI**.
- A **real LTE attach** — a [**srsRAN**](https://www.srsran.com/) UE → Open5GS MME → `udr` — drives the full S6a control plane end to end: authentication (`AIR`/`AIA`) and location update (`ULR`/`ULA`).

Each result is a reproducible demo in [`demos/`](demos/) (two are CI-gated; the full attach is a one-command local run), and the running interoperability record is in [`docs/manual/compatibility.md`](docs/manual/compatibility.md).

> Testing against the real stack earns its keep: the first real Open5GS `AIR` to reach `udr` surfaced an S6a decode bug the unit tests never hit — captured as a PCAP, fixed, and re-verified against the live attach.

## Architecture

This is a rebar3 umbrella. Each app is a single, well-scoped responsibility:

| App | Responsibility |
| --- | --- |
| `udr_crypto` | Authentication crypto primitives (MILENAGE, EPS-AKA) |
| `udr_db` | Pluggable generic document store (selects a backend at runtime) |
| `udr_db_mongo` | MongoDB backend for `udr_db` |
| `udr_data` | Nudr-shaped data-access seam between the HSS logic and `udr_db` |
| `udr_cluster` | Cluster-wide per-IMSI session locking over `syn` |
| `udr_hss` | S6a HSS application logic (AIR / ULR / PUR) |
| `udr_diameter` | S6a Diameter wire layer (codec + transport) |
| `udr_sbi` | Nudr-flavoured 5G SBI (data repository) HTTP server |
| `udr_provision` | Admin provisioning HTTP API |
| `udr_otel` | OpenTelemetry setup: metric instruments + span exporter |
| `udr` | Top-level release application |

The HSS logic talks to subscriber data only through `udr_data`, which talks only through `udr_db`. Swapping ETS for MongoDB — or adding another backend — touches no signalling code.

## Requirements

- **Erlang/OTP 29+**
- **rebar3**
- **MongoDB** — *optional*, only if you select the MongoDB backend (the default ETS backend needs nothing external)

## Quick start

### Run the published image — no build, no database

```sh
docker run --rm -p 3868:3868 -p 8080:8080 -p 8090:8090 ghcr.io/next-nf/udr:latest
```

(or `podman run …` — the image is multi-arch, `amd64` + `arm64`.) Then, in another
terminal, provision a subscriber and read it back over the 5G SBI:

```sh
curl -fsS -X PUT -H 'content-type: application/json' \
  -d '{"auth":{"ki":"465b5ce8b199b49faa5f0a2ee238a6bc","opc":"cd63cb71954a9f4e48a5994e37a02baf","amf":"8000"}}' \
  http://127.0.0.1:8090/provision/v1/subscribers/001010000000001

curl -fsS http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/authentication-data/authentication-subscription
```

The default backend is in-memory ETS — nothing else to install. To watch a full S6a
authentication exchange (AIR/ULR) against a Diameter client, run
[`demos/s6a-smoke`](demos/s6a-smoke/).

### Build from source

```sh
rebar3 compile      # build
rebar3 shell        # interactive node — Diameter, SBI, and provisioning all start
```

With the default `config/sys.config`, a `rebar3 shell` node listens on:

| Interface | Address | Purpose |
| --- | --- | --- |
| S6a Diameter | `127.0.0.1:3868` (TCP) | MME ↔ HSS signalling |
| SBI (Nudr-DR) | `127.0.0.1:8080` | 5G subscriber data |
| Provisioning | `127.0.0.1:8090` | Admin subscriber management |

The default data backend is **in-memory ETS**, so a fresh node needs no database.

## Interfaces

### S6a (Diameter)

Application logic for the commands an MME issues against an EPC HSS:

- **AIR** — Authentication-Information-Request → returns EPS authentication vectors (MILENAGE).
- **ULR** — Update-Location-Request → registers the serving MME and returns subscription data.
- **PUR** — Purge-UE-Request → clears purged-UE state.
- **CLR** — Cancel-Location-Request → HSS-initiated, e.g. on re-registration from a new MME.

### 5G SBI — Nudr-DR (`udr_sbi`, default `:8080`)

Resources under `/nudr-dr/v1/subscription-data/{ueId}`:

| Method | Path | Resource |
| --- | --- | --- |
| `GET` | `/authentication-data/authentication-subscription` | Authentication subscription |
| `GET` | `/provisioned-data/am-data` | Access-and-mobility subscription data |
| `GET` `PUT` `DELETE` | `/context-data/amf-3gpp-access` | AMF 3GPP-access registration context |

### Provisioning API (`udr_provision`, default `:8090`)

| Method | Path | Action |
| --- | --- | --- |
| `PUT` | `/provision/v1/subscribers/{imsi}` | Create / update a subscriber |
| `GET` | `/provision/v1/subscribers/{imsi}` | Read a subscriber |
| `DELETE` | `/provision/v1/subscribers/{imsi}` | Delete a subscriber |

## Configuration

Runtime configuration lives in [`config/sys.config`](config/sys.config). Key sections:

```erlang
%% Data backend: udr_db_ets (default, in-memory) or udr_db_mongo
{udr_db, [{backend, udr_db_ets}, {backend_opts, #{}}]},

%% S6a Diameter identity and listener
{udr_diameter, [
  {origin_host,  "hss.epc.mnc001.mcc001.3gppnetwork.org"},
  {origin_realm, "epc.mnc001.mcc001.3gppnetwork.org"},
  {listen, [{tcp, {127,0,0,1}, 3868}]}
]},

%% HTTP listeners
{udr_provision, [{port, 8090}, {ip, {127,0,0,1}}]},
{udr_sbi,       [{port, 8080}, {ip, {127,0,0,1}}]},
```

To use MongoDB, set the backend to `udr_db_mongo` and supply connection options in `backend_opts`.

## Observability

OpenTelemetry is built in. By default the trace exporter is `none`; point it at a collector by setting `traces_exporter` and the OTLP endpoint in `config/sys.config`:

```erlang
{opentelemetry, [{span_processor, batch}, {traces_exporter, otel_exporter_otlp}]},
{opentelemetry_exporter, [{otlp_protocol, http_protobuf},
                          {otlp_endpoint, "http://localhost:4318"}]},
```

S6a commands and HTTP requests produce spans (e.g. `s6a.AIR`, `s6a.ULR`, `s6a.PUR`), with the HSS-initiated CLR linked back to the ULR that triggered it.

## Development

```sh
rebar3 compile        # build
rebar3 ct             # run the Common Test suites
rebar3 dialyzer       # type analysis
rebar3 ex_doc         # generate API docs (EEP-48 -doc/-moduledoc, rendered with ExDoc)
```

Tests are Common Test, with property-based tests via [PropEr](https://hex.pm/packages/proper).

## License

[GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). If you run a modified version as a network service, the AGPL requires you to offer that modified source to its users.
