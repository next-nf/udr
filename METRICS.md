# Metrics Reference

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-11

This document is the operator-facing catalogue of the [OpenTelemetry](docs/manual/glossary.md) metric instruments the `udr` node emits. It is the metrics half of the observability contract; the trace spans and the exporter/reader configuration are documented in the [observability configuration reference](docs/manual/configuration/observability.md) and the [observability runbook](docs/manual/operations/observability.md).

This index is informative; the per-instrument tables below are the normative contract. Every instrument listed here is created at node start by the `udr_otel` application and recorded on the live S6a request path; none requires configuration to be produced. How they are *collected and exported* is set by the `opentelemetry_experimental` metric readers — see the observability configuration reference.

## 1. Conventions

- Instruments are named with dot-separated, lowercase [OTEL semantic](docs/manual/glossary.md) namespaces: `<interface>.<subject>`. The interface namespace (`s6a`) lines up with the [S6a interface reference](docs/manual/interfaces/s6a.md).
- Dimensions are carried as OTEL **attributes**, not baked into the instrument name.
- Durations are recorded in **base units (seconds)**, per OTEL semantic conventions; the unit is set on the instrument.
- Each attribute value below is the exact term the code emits. `s6a.command` carries the [Diameter](docs/manual/glossary.md) command name; `s6a.result` carries the outcome.

## 2. Instruments

| Instrument | Type | Unit | Attributes | Measures | Since |
| --- | --- | --- | --- | --- | --- |
| `s6a.requests` | Counter (monotonic) | `1` | `s6a.command`, `s6a.result` | One increment per S6a request handled by the Diameter callback. | 0.1.0 |
| `s6a.handler.duration` | Histogram | `s` (seconds) | `s6a.command`, `s6a.result` | Wall-clock latency of the S6a request handler, from request receipt to answer. | 0.1.0 |

Both instruments are recorded together, once per request, by `udr_otel:record_s6a/3` (called from `udr_diameter_s6a:handle_request/3`). A request therefore contributes exactly one count to `s6a.requests` and one observation to `s6a.handler.duration`, with identical attributes on both.

### 2.1 Attributes

| Attribute | Values | Meaning |
| --- | --- | --- |
| `s6a.command` | `AIR`, `ULR`, `PUR` | The S6a command the request carried. HSS-initiated CLR is not counted here (it is originated, not handled). |
| `s6a.result` | `success`, or an error reason | `success` when the handler produced a successful answer; otherwise the error reason. The error reasons the code emits today are `user_unknown`, `unknown_eps_subscription`, and `session_busy`; any other handler error is reported as `unable_to_comply`. New reasons `may` appear as the handler grows, so a dashboard or alert `should` treat any non-`success` value as an error rather than enumerate a fixed set. |

> [!NOTE]
> *(Informative.)* The same S6a path also produces trace spans (`s6a.AIR`, `s6a.ULR`, `s6a.PUR`) carrying the `s6a.command` and `s6a.result` attributes, and HTTP spans for the SBI and provisioning listeners via `opentelemetry_cowboy_h`. Spans are documented in the [S6a interface reference](docs/manual/interfaces/s6a.md) §8, not here; this document covers metric instruments only.

## 3. Backend and naming under the Prometheus exporter

The committed Grafana dashboard (`dashboards/udr.json`, §4) targets a **Prometheus-compatible store fed by the OTEL Prometheus exporter**. When metrics are exported that way, the OTEL→Prometheus naming transform applies, so the instruments above appear under these series:

| OTEL instrument | Prometheus series | Notes |
| --- | --- | --- |
| `s6a.requests` | `s6a_requests_total` | Dots become underscores; the monotonic counter gains the `_total` suffix. |
| `s6a.handler.duration` | `s6a_handler_duration_seconds` | Exposed as `_bucket`, `_sum`, and `_count` series; the `s` unit becomes the `_seconds` suffix. |
| attribute `s6a.command` | label `s6a_command` | |
| attribute `s6a.result` | label `s6a_result` | |

> [!NOTE]
> If metrics are instead consumed natively over [OTLP](docs/manual/glossary.md) (no Prometheus exporter), the instruments keep their dotted OTEL names and the transform above does not apply. The dashboard ships against the Prometheus naming because that is the store it targets.

## 4. Grafana dashboard

One dashboard is maintained for the component, checked in as a JSON model so it diffs in review:

- `dashboards/udr.json` — the S6a overview: request rate by command, result/error rate, handler latency percentiles, and a success-ratio stat.

The dashboard and this reference `shall` stay in sync: a metric added here without a panel, or a panel referencing a series not listed here, is a defect. The dashboard expects a Prometheus-compatible datasource (selectable at import via the `DS_PROMETHEUS` variable) carrying the series in §3.

## 5. Verify

*(Observable outcome.)* With a metric reader configured (see the [observability configuration reference](docs/manual/configuration/observability.md) §4) and S6a traffic driven against the node:

- `s6a.requests` `shall` increase by one per S6a request, partitioned by `s6a.command` and `s6a.result`. Drive one [AIR](docs/manual/glossary.md) for a provisioned [IMSI](docs/manual/glossary.md) and confirm a `success`/`AIR` increment; drive one for an unprovisioned IMSI and confirm a `user_unknown`/`AIR` increment.
- `s6a.handler.duration` `shall` record one observation per request with the same attributes; its `_count` `shall` track the `s6a.requests` total for the same attribute set.
- Under the Prometheus exporter, confirm the series `s6a_requests_total` and `s6a_handler_duration_seconds_bucket` are present at the scrape endpoint.
