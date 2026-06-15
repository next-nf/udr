# Metrics Reference

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-15

This document is the operator-facing catalogue of the [OpenTelemetry](docs/manual/glossary.md) metric instruments the `udr` node emits. It is the metrics half of the observability contract; the trace spans and the exporter/reader configuration are documented in the [observability configuration reference](docs/manual/configuration/observability.md) and the [observability runbook](docs/manual/operations/observability.md).

The node emits two kinds of instrument:

- **Hand-defined** instruments created by the `udr_otel` application — the S6a request instruments (§2).
- **Library-emitted** instruments registered by the OpenTelemetry instrumentation libraries the node depends on — HTTP server metrics (§3), Diameter stack metrics (§4), and BEAM/VM + process metrics (§5).

This index is informative; the per-instrument tables below are the normative contract. None of these instruments requires configuration to be produced. How they are *collected and exported* is set by the `opentelemetry_experimental` metric readers — see the observability configuration reference.

## 1. Conventions

- Instruments are named with dot-separated, lowercase [OTEL semantic](docs/manual/glossary.md) namespaces: `<area>.<subject>`. The interface namespaces (`s6a`, `http`, `diameter`) line up with the [interfaces reference](docs/manual/interfaces/README.md).
- Dimensions are carried as OTEL **attributes**, not baked into the instrument name.
- Durations are recorded in **base units (seconds)**, sizes in **bytes (`By`)**, per OTEL semantic conventions; the unit is set on the instrument.
- Instruments are either **synchronous** (recorded inline on the request path: the S6a and HTTP instruments) or **observable** (a callback the SDK invokes at collection time: the Diameter, BEAM and process instruments). Observable instruments impose no per-request cost; they sample state when metrics are collected.

## 2. S6a request instruments

Created at node start by `udr_otel` and recorded on the live S6a request path.

| Instrument | Type | Unit | Attributes | Measures | Since |
| --- | --- | --- | --- | --- | --- |
| `s6a.requests` | Counter (monotonic) | `{request}` | `s6a.command`, `s6a.result` | One increment per S6a request handled by the Diameter callback. | 0.1.0 |
| `s6a.handler.duration` | Histogram | `s` (seconds) | `s6a.command`, `s6a.result` | Wall-clock latency of the S6a request handler, from request receipt to answer. | 0.1.0 |

Both instruments are recorded together, once per request, by `udr_otel:record_s6a/3` (called from `udr_diameter_s6a:handle_request/3`). A request therefore contributes exactly one count to `s6a.requests` and one observation to `s6a.handler.duration`, with identical attributes on both.

### 2.1 Attributes

| Attribute | Values | Meaning |
| --- | --- | --- |
| `s6a.command` | `AIR`, `ULR`, `PUR` | The S6a command the request carried. HSS-initiated CLR is not counted here (it is originated, not handled). |
| `s6a.result` | `success`, or an error reason | `success` when the handler produced a successful answer; otherwise the error reason. The error reasons the code emits today are `user_unknown`, `unknown_eps_subscription`, and `session_busy`; any other handler error is reported as `unable_to_comply`. New reasons `may` appear as the handler grows, so a dashboard or alert `should` treat any non-`success` value as an error rather than enumerate a fixed set. |

> [!NOTE]
> *(Informative.)* The same S6a path also produces trace spans (`s6a.AIR`, `s6a.ULR`, `s6a.PUR`) carrying the `s6a.command` and `s6a.result` attributes. Spans are documented in the [S6a interface reference](docs/manual/interfaces/s6a.md) §8, not here; this document covers metric instruments only.

## 3. HTTP server instruments

Emitted by the `opentelemetry_cowboy_h` stream handler for **both** Cowboy listeners — the Nudr SBI (`:8080`) and the provisioning API (`:8090`). The handler emits HTTP **spans** automatically; the **metrics** below are opt-in and are enabled by the node: `opentelemetry_cowboy_experimental_h:init/0` creates the instruments at listener start and the listener passes `metrics_cb` so each completed request is recorded.

| Instrument | Type | Unit | Measures | Since |
| --- | --- | --- | --- | --- |
| `http.server.request.duration` | Histogram | `s` (seconds) | Wall-clock duration of each HTTP request. | 0.1.0 |
| `http.server.request.body.size` | Histogram | `By` (bytes) | Request body size; recorded only when the size is a number. | 0.1.0 |
| `http.server.response.body.size` | Histogram | `By` (bytes) | Response body size. | 0.1.0 |

### 3.1 Attributes

Each histogram carries the **stable** HTTP OTEL semantic-convention attributes that the handler populates:

| Attribute | Meaning |
| --- | --- |
| `http.request.method` | Request method (`GET`, `PUT`, `DELETE`, …). |
| `url.scheme` | `http` (the listeners are clear; TLS terminates upstream). |
| `http.response.status_code` | Numeric HTTP status of the answer. |
| `network.protocol.name`, `network.protocol.version` | Application protocol and version (e.g. `http`, `1.1`). |
| `server.address`, `server.port` | The listening address and port the request hit. |

> [!WARNING]
> *(Operational caveats — confirmed from the handler source.)*
> - **`http.route` and `error.type` are not populated.** They are in the handler's attribute filter but Cowboy does not hand it a matched-route string and `error.type` is never set, so these two dimensions are **absent**. Per-route latency breakdowns are not available without adding the attribute yourself; do not build dashboards or alerts that group by `http.route`.
> - **`http.server.response.body.size` is recorded even when the size is `undefined`.** Treat anomalous values on that histogram with skepticism.
> - **Spans and metrics use different attribute vintages.** The HTTP span carries the *legacy* keys (`http.method`, `http.status_code`, …); these metrics carry the *stable* semconv keys (`http.request.method`, `http.response.status_code`, …). Do not expect span and metric attribute keys to line up.

## 4. Diameter instruments

Emitted by `opentelemetry_diameter`, which samples the OTP `diameter` stack's own statistics for the S6a service at collection time. All six are **observable** (pull-based); registered once by `udr_otel:setup_instrumentation/0`.

| Instrument | Type | Unit | Measures | Since |
| --- | --- | --- | --- | --- |
| `diameter.application.count` | Observable up/down counter | `{application}` | Diameter applications installed on the service. | 0.1.0 |
| `diameter.connection.count` | Observable up/down counter | `{connection}` | Current peer connections. | 0.1.0 |
| `diameter.message.count` | Observable counter (monotonic) | `{request}` | Messages sent/received, partitioned by command and result. | 0.1.0 |
| `diameter.connection.io` | Observable counter (monotonic) | `By` (bytes) | Bytes transferred over connections. | 0.1.0 |
| `diameter.connection.packets` | Observable counter (monotonic) | `{packet}` | Packets transferred over connections. | 0.1.0 |
| `diameter.error.count` | Observable counter (monotonic) | `{error}` | Messages that errored or carried a non-success result. | 0.1.0 |

### 4.1 Attributes

The instruments carry a subset of the following, depending on the metric: `diameter.service.name`, `diameter.peer.origin_host`, `diameter.peer.origin_realm`, `diameter.role`, `network.transport`, `network.local.address`, `network.io.direction` (`receive`/`transmit`), `diameter.connection.watchdog.state`, `message.direction` (`received`/`sent`), `diameter.command.type` (`request`/`answer`), `diameter.command.code`, `diameter.application.id`, `diameter.result_code`, and `diameter.error.type`.

> [!NOTE]
> *(Informative.)* The exact unit/attribute contract is owned by the library, not this repo. See the [`opentelemetry_diameter` README](https://github.com/next-nf/opentelemetry-erlang-contrib/tree/main/instrumentation/opentelemetry_diameter) (the next-nf fork the node pins) for the authoritative per-metric detail, and the [observability policy](https://github.com/next-nf) for how these map onto the interface namespaces. These metrics give a Diameter-level view of S6a that complements the application-level §2 instruments.

## 5. BEAM/VM and process instruments

The node also runs `opentelemetry_beam` (BEAM/VM runtime: schedulers, run queues, memory, atoms, ETS/DETS, ports, garbage collection) and `opentelemetry_process` (per-process: memory, reductions, message-queue, file descriptors, uptime). Both register observable instruments under the `beam.*` and `process.*` namespaces via `udr_otel:setup_instrumentation/0`.

> [!NOTE]
> *(Informative.)* These instruments' names, units, and attributes are **not defined by this repo**; they track the next-nf **semantic conventions (BEAM VM)** branch, which is their source of truth:
> <https://github.com/next-nf/semantic-conventions/tree/add/beam-vm>
>
> The `beam.*` set is large (memory by class, scheduler counts and utilisation, run-queue lengths, atom/ETS/DETS counts and limits, port counts and I/O, GC reclaim) and the `process.*` set covers `process.memory.usage`, `process.thread.count`, `process.open_file_descriptor.count`, `process.uptime`, and similar. Align any dashboard or alert against the conventions branch above rather than hard-coding names here, which would drift.

## 6. Export pipelines and Prometheus naming

The node defines metrics as native OTEL instruments and exposes them two ways, both configured by the `opentelemetry_experimental` readers (see the [observability configuration reference](docs/manual/configuration/observability.md)):

1. **OTLP push (preferred).** Metrics are exported in native OTEL form to an OTLP collector (for example **Grafana Alloy**), which applies the OTEL→Prometheus name transform on the way into a Prometheus-compatible store. This is the pipeline the Grafana dashboard (§7) is authored for.
2. **In-process OTEL Prometheus exporter.** The node also serves a Prometheus text exposition at **`GET :9464/metrics`** (the `udr_otel` `metrics_port`), for direct scraping. It applies the same OTEL→Prometheus transform, so the series match the OTLP→collector path.

The OTEL→Prometheus transform: dots become underscores, monotonic counters gain `_total`, histograms expand to `_bucket`/`_sum`/`_count` (plus a `_created` series), the unit becomes a suffix (`s`→`_seconds`, `By`→`_bytes`), curly-brace annotation units (`{request}`) are dropped, and attribute keys become labels (dots to underscores).

The series below were **confirmed against the live `:9464/metrics` endpoint**:

| OTEL instrument | Prometheus series |
| --- | --- |
| `s6a.requests` | `s6a_requests_total` (labels `s6a_command`, `s6a_result`) |
| `s6a.handler.duration` | `s6a_handler_duration_seconds_bucket` / `_sum` / `_count` |
| `http.server.request.duration` | `http_server_request_duration_seconds_bucket` / `_sum` / `_count` |
| `http.server.response.body.size` | `http_server_response_body_size_bytes_bucket` / `_sum` / `_count` |
| `diameter.message.count` | `diameter_message_count_total` (labels incl. `message_direction`) |
| `diameter.error.count` | `diameter_error_count_total` (label `diameter_error_type`) |
| `diameter.connection.count` | `diameter_connection_count` (observable up/down counter — no `_total`) |

> [!IMPORTANT]
> The dimensionless unit `1` maps to a `_ratio` suffix under the transform — a counter declared with unit `1` becomes `<name>_ratio_total`, not `<name>_total`. `s6a.requests` therefore uses the annotation unit `{request}` (which is stripped) so it exposes cleanly as `s6a_requests_total`. Declare count instruments with an annotation unit, not `1`.

> [!NOTE]
> If a collector is configured **not** to add metric suffixes (`add_metric_suffixes`/`add_total_suffix` disabled), counters appear without `_total` and histograms without unit suffixes. The node's `:9464` exporter sets `add_total_suffix => true` to match the standard convention the dashboard targets; align the collector to the same setting.

## 7. Grafana dashboard

One dashboard is maintained for the component, checked in as a JSON model so it diffs in review:

- `dashboards/udr.json` — covers the **signalling surface**: the S6a request rate, result/error rate, and handler-latency percentiles (§2); the HTTP request rate and latency for the SBI and provisioning listeners (§3); and the Diameter message/error rate (§4). Its PromQL targets the confirmed §6 series, which are produced identically by the OTLP→collector path and the `:9464` exporter.

The BEAM/VM and process instruments (§5) are documented by reference and are available on the same datasource; they are intentionally not paneled here — align a VM/runtime dashboard to the semantic-conventions branch in §5 rather than to fixed names in this repo.

The dashboard and this reference `shall` stay in sync for the signalling surface: a §2–§4 metric added without a panel, or a panel referencing a series not listed here, is a defect. The dashboard expects a Prometheus-compatible datasource (selectable at import via the `DS_PROMETHEUS` variable) carrying the series in §6.

## 8. Verify

*(Observable outcome.)*

- **Scrape endpoint** — `curl :9464/metrics` `shall` return `200` and a Prometheus text exposition. After driving traffic, confirm `s6a_requests_total` and `http_server_request_duration_seconds_bucket` are present.
- **S6a** — drive one [AIR](docs/manual/glossary.md) for a provisioned [IMSI](docs/manual/glossary.md): `s6a_requests_total{s6a_command="AIR",s6a_result="success"}` `shall` increase by one and `s6a_handler_duration_seconds_count` track it. Drive one for an unprovisioned IMSI: confirm an `s6a_result="user_unknown"` increment.
- **HTTP** — issue one request to the provisioning API (`:8090`) or SBI (`:8080`): `http_server_request_duration_seconds_count` `shall` gain one observation carrying `http_request_method` and `http_response_status_code` (note: `http_route` is **not** populated — see §3.1).
- **Diameter** — with the S6a service up and a peer connected, `diameter_connection_count` `shall` report at least one connection and `diameter_message_count_total` `shall` be non-zero after traffic.
- **BEAM/process** — `beam_memory_system_bytes` and `process_uptime_seconds` `shall` be present at the scrape endpoint.
