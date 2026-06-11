# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A converged 3GPP **HSS + UDR/UDM** in Erlang/OTP. It speaks **S6a Diameter** to an MME (EPC HSS role) and exposes a **5G Nudr-DR Service-Based Interface** for subscriber data, over a pluggable document store, clustered for per-subscriber consistency, with OpenTelemetry built in. Status is early (v0.1.0). Requires **OTP 29+** (uses experimental native-record syntax). License is **AGPL-3.0**.

## Commands

```sh
rebar3 compile        # build
rebar3 ct             # run all Common Test suites
rebar3 dialyzer       # type analysis (CI runs this on every push/PR)
rebar3 shell          # interactive release: Diameter :3868, SBI :8080, provisioning :8090, ETS backend
rebar3 ex_doc         # generate API docs from EEP-48 -doc/-moduledoc (NOT edoc)
rebar3 as container release   # assemble the prod release with container config (the image build runs this)
```

Run a single suite / case / group:

```sh
rebar3 ct --suite=apps/udr_hss/test/udr_hss_SUITE
rebar3 ct --suite=apps/udr_hss/test/udr_hss_SUITE --case=air_returns_vectors
rebar3 ct --dir=apps/udr_data/test
```

The **multi-node peer suites** (`udr_hss_dist_SUITE`, `udr_cluster_dist_SUITE`) need a
distributed CT node — start CT with a name, e.g. `rebar3 ct --sname test`. They do **not**
start distribution themselves; without `--sname`/`--name` they skip cleanly (they never fail
the run). CI runs `rebar3 ct --sname test` for this reason.

The CI pipeline (`.github/workflows/ci.yml`) is the source of truth for the expected toolchain: **OTP 29**, **rebar3 3.26.0**. The `test` job runs compile → dialyzer → ct; the image is built separately (see below). Match it before claiming work is done.

The container image is built with **podman/buildah** (not docker). Its assets live in `container/` (`Containerfile`, `container.sys.config`); the build context is the repo root and `.containerignore` controls it. Build locally with `podman build -f container/Containerfile -t udr .`. CI builds multi-arch (linux/amd64 + linux/arm64) on native runners and merges a manifest.

## Architecture

rebar3 umbrella; each app under `apps/` is one well-scoped responsibility. The defining rule is a **strict data-access layering** — signalling code never touches storage directly:

```
udr_hss / udr_diameter / udr_sbi / udr_api   (signalling + interfaces)
        │  (only through)
        ▼
udr_data        Nudr-shaped, domain-aware seam (auth subscription, am-data, registration, SQN)
        │  (only through)
        ▼
udr_db          generic document store facade: get/put/delete/find/update (version-CAS)
        │  (dispatches to)
        ▼
udr_db_ets (default, in-memory)   |   udr_db_mongo (optional)
```

Swapping or adding a backend touches no signalling code. Respect this layering when adding features — put domain semantics in `udr_data`, keep `udr_db`/backends domain-agnostic.

Key mechanisms that span multiple files:

- **Backend selection** (`udr_db:backend/0`): the configured backend module (`{udr_db, backend}` env, default `udr_db_ets`) is resolved once and **cached in `persistent_term`**. Changing the backend at runtime requires a node restart.
- **Backend contract** (`udr_db_backend.erl`): a generic doc store keyed by `collection() :: atom()` / `key() :: binary()`, docs are `#{binary() => term()}`. Updates are an **atomic compare-and-swap on an internal `version` token** (`update/4` applies a mutation iff the stored version matches, then bumps it). `udr_db:put/3` seeds `version => 1`.
- **The `version` CAS token is hidden from `udr_data` callers.** `udr_data` retries CAS up to `?CAS_RETRIES` (100) on conflict for operations like `advance_sqn`/`repair_sqn`. Don't leak the version field up into interface code.
- **Per-IMSI cluster locking** (`udr_cluster:with_session/2,3`): serialises concurrent signalling for one subscriber across nodes via [`syn`](https://hex.pm/packages/syn). HSS flows that mutate a subscriber wrap work in a session lock (default 5s acquire timeout).
- **Release boot ordering** (`relx` in `rebar.config`): `udr_db_mongo` is `{load}`-only — its code is loaded so `udr_db` can select it at runtime, but the `mongodb` driver app is started lazily (by `udr_db_mongo_conn`) so ETS-only deployments never boot the driver.

## Interfaces (default ports)

- **S6a Diameter** `:3868` — AIR (auth vectors, MILENAGE), ULR (register serving MME), PUR (purge), HSS-initiated CLR. Wire codec/transport in `udr_diameter`; command logic in `udr_hss`.
- **Nudr-DR SBI** `:8080` — `/nudr-dr/v1/subscription-data/{ueId}/...` (auth subscription, am-data, amf-3gpp-access context). Cowboy handlers in `udr_sbi`.
- **Provisioning API** `:8090` — `PUT/GET/DELETE /provision/v1/subscribers/{imsi}`. Cowboy handlers in `udr_api`.

Runtime config: `config/sys.config` (local), `container/container.sys.config` (container, binds 0.0.0.0). MILENAGE auth crypto (f1–f5/f1*/f5*/OPc per TS 35.205/206) lives in `udr_crypto` behind a pluggable algorithm behaviour.

## Gotchas when writing tests

- **OpenTelemetry is a process-global singleton.** The first CT suite to start the SDK fixes its exporter for the entire `rebar3 ct` node. `config/ct.sys.config` (loaded via `{ct_opts, {sys_config, ...}}`) therefore makes `udr_otel_pid_exporter` the SDK default for the whole run; it drops spans unless a testcase calls `udr_otel_pid_exporter:capture_to(self())`. Read `config/ct.sys.config` before touching OTel test setup.
- **Mongo-backed suites** (`udr_db_mongo_conformance_SUITE`, `udr_hss_dist_SUITE`) detect `CI=true` and use the `MONGO_HOST`/`MONGO_PORT` service; locally they start their own podman container. Helper: `apps/udr_db_mongo/test/udr_mongo_ct.erl`.
- Property-based tests use **PropEr** (test profile dep).

## Build-config quirks (don't "fix" these without understanding them)

`rebar.config` carries several deliberate workarounds, each with an inline comment explaining why: a global `nowarn_deprecated_catch` override (ts_chatterbox under OTP-29 + warnings_as_errors); `dialyzer` `plt_extra_apps` so Cowboy/ranch types resolve; and an `edoc_opts` `source_suffix` set to a non-matching suffix plus a `pre_hooks` mkdir, both purely to make `rebar3 ex_doc` skip the broken edoc pass (edoc can't parse the OTP-29 native-record syntax in `udr_crypto`) while ExDoc reads docs from the `.beam` EEP-48 chunks. Read the comment before changing any of them.

## Documentation

Operator-facing docs live in `docs/manual/` and follow the project's **ETSI-derived documentation standard**. When writing or updating operator docs (configuration references, runbooks, troubleshooting, diagrams), use the `documenting-hss` skill.
