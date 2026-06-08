# Troubleshooting: Observability (OpenTelemetry)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers the symptom an operator observes when [OpenTelemetry](../glossary.md) telemetry does not reach the collector: no `s6a.*` spans and no `s6a.requests` / `s6a.handler.duration` metrics appear at the configured [OTLP](../glossary.md) destination. The OpenTelemetry keys are defined in the [observability configuration reference](../configuration/observability.md); enabling export is the procedure [`RUN-OBSERVABILITY-001`](../operations/observability.md).

> [!IMPORTANT]
> With the shipped configuration, `traces_exporter` is `none`: spans are produced internally but exported nowhere. No spans at the collector is therefore the **expected** behavior of a fresh checkout, not a fault. The entries below separate that expected default from an export that is enabled but not arriving.

---

## TS-OBS-001: No spans appear at the collector

### Symptom

After driving S6a traffic (for example an `AIR`), no `s6a.AIR`, `s6a.ULR`, or `s6a.PUR` span appears at the OTLP collector for this node's `service.name`.

### Affected component

The OpenTelemetry trace pipeline: the `opentelemetry` `traces_exporter` setting and the `opentelemetry_exporter` OTLP transport.

### Likely causes

*(Ordered, most probable first.)*

1. `traces_exporter` is `none` (the shipped default), so spans are produced internally but never exported. This is the most common reason and is the expected default.
2. `traces_exporter` is `otlp`, but `otlp_endpoint` points at a collector that is wrong or unreachable from the node.
3. `traces_exporter` is `otlp` and the endpoint is reachable, but `otlp_protocol` does not match the transport/port the collector accepts (for example `http_protobuf` to port `4318` versus `grpc` to port `4317`).
4. No S6a traffic was actually driven, so no span was produced to export.

### Diagnosis

1. Confirm the resolved exporter setting. At the node's console:
   ```erlang
   application:get_env(opentelemetry, traces_exporter).
   ```
   - Expected when export is enabled: `{ok, otlp}`.
   - If it is `{ok, none}`, nothing is exported — cause 1. This is the shipped default.
2. Confirm the configured endpoint and transport. At the node's console:
   ```erlang
   {application:get_env(opentelemetry_exporter, otlp_endpoint),
    application:get_env(opentelemetry_exporter, otlp_protocol)}.
   ```
   - Expected: an endpoint URL the collector serves, and a protocol the collector accepts.
3. Confirm the collector endpoint is reachable from the node's host. For the shipped `http_protobuf` transport on the default OTLP/HTTP port:
   ```sh
   nc -vz <collector-host> 4318
   ```
   - Expected: the connection succeeds.
   - If it fails, the collector is unreachable from the node — cause 2.
   - If it succeeds but no span arrives, confirm the port matches the protocol — `http_protobuf` corresponds to `4318`, `grpc` to `4317` — cause 3.
4. Confirm a span was actually produced. Drive one `AIR` against any IMSI (a provisioned one yields `s6a.result` = `success`; an unprovisioned one still yields a span with `s6a.result` = `user_unknown`), per [`RUN-S6A-PEER-001`](../operations/s6a-peer.md).
   - Expected: a span is produced for every handled `AIR`/`ULR`/`PUR`.
   - If no S6a request reached the node, no span exists to export — cause 4.

### Resolution

*(Normative.)*

- For cause 1: to export spans, `traces_exporter` `shall` be set to `otlp`, per the [observability configuration reference §5.1](../configuration/observability.md#51-traces_exporter-and-the-otlp-endpoint), and the node restarted. Where no collector is in use, `none` `should` be kept; the absence of spans is then expected.
- For cause 2: `otlp_endpoint` `shall` point at a reachable OTLP collector.
- For cause 3: `otlp_protocol` `shall` match a transport the configured collector accepts, with the endpoint port matching the protocol.
- For cause 4: S6a traffic `shall` be driven (an `AIR`, `ULR`, or `PUR`) for a span to be produced; no traffic means no span, independent of the exporter.

> [!NOTE]
> The `opentelemetry_exporter` block is present in the shipped configuration even though `traces_exporter` is `none`, so that enabling export needs only the one change to `traces_exporter`. On its own the exporter block exports nothing (per the [observability configuration reference §3](../configuration/observability.md#3-where-configuration-lives)).

### Prevention

*(Informative.)* Enabling export and confirming an `s6a.AIR` span at the collector is the procedure [`RUN-OBSERVABILITY-001`](../operations/observability.md); its [Verify step](../operations/observability.md#verify) confirms `{ok, otlp}` and a span at the collector before telemetry is relied upon. The verification of the collector reachability and the protocol/port match is the same checklist as its [on-failure guidance](../operations/observability.md#rollback--on-failure).

### Related

- [Observability configuration reference §3, §5.1, §7](../configuration/observability.md#3-where-configuration-lives) — `traces_exporter`, the OTLP endpoint, and the verification.
- [`RUN-OBSERVABILITY-001`](../operations/observability.md) — export traces and metrics.
- [S6a interface reference §8](../interfaces/s6a.md#8-verify) — the `s6a.AIR` span and its `s6a.result` attribute.

---

## TS-OBS-002: No metrics appear at the collector

### Symptom

The S6a metric instruments `s6a.requests` and `s6a.handler.duration` do not appear in the collector's metric view, even though S6a traffic has been driven.

### Affected component

The OpenTelemetry metric pipeline: the `opentelemetry_experimental` `readers` and the OTLP exporter that drains them.

### Likely causes

*(Ordered, most probable first.)*

1. No collector is configured or reachable to receive metrics — the same endpoint/transport conditions as [TS-OBS-001](#ts-obs-001-no-spans-appear-at-the-collector) causes 2 and 3.
2. No S6a traffic was driven, so the instruments recorded nothing to report.
3. The metric reader configuration in `opentelemetry_experimental` `readers` does not route the instruments to an exporter that reaches the collector.

### Diagnosis

1. Confirm the metric reader configuration. At the node's console:
   ```erlang
   application:get_env(opentelemetry_experimental, readers).
   ```
   - Expected: the reader specification, the shipped value being `[#{module => otel_metric_reader, config => #{}}]`.
   - If it is empty or names no reader, no instrument is collected — cause 3.
2. Confirm the collector endpoint is reachable from the node's host, as in [TS-OBS-001](#ts-obs-001-no-spans-appear-at-the-collector) Step 3:
   ```sh
   nc -vz <collector-host> 4318
   ```
   - Expected: the connection succeeds. A failure is cause 1.
3. Confirm S6a traffic was driven. The instruments are recorded on each handled `AIR`/`ULR`/`PUR` (confirmed in `udr_diameter_s6a.erl`, `udr_otel:record_s6a/3`).
   - Expected: at least one S6a request has been handled since the node started.
   - If none has, the instruments have nothing to report — cause 2.

### Resolution

*(Normative.)*

- For cause 1: a reachable collector `shall` be configured for metrics to be delivered, per the [observability configuration reference §5.1](../configuration/observability.md#51-traces_exporter-and-the-otlp-endpoint); the same endpoint/transport requirements as for spans apply.
- For cause 2: S6a traffic `shall` be driven for the `s6a.requests` and `s6a.handler.duration` instruments to record and report.
- For cause 3: `opentelemetry_experimental` `readers` `shall` configure a metric reader; the shipped reader `should` be kept unless a different reader is deliberately chosen (per the [observability configuration reference §4](../configuration/observability.md#4-parameter-reference)).

> [!NOTE]
> The `udr_otel` application creates the `s6a.requests` and `s6a.handler.duration` instruments at start and records to them; it reads no configuration of its own. The instruments report under whatever reader `opentelemetry_experimental` `readers` configures (per the [observability configuration reference §1](../configuration/observability.md#1-scope)).

### Prevention

*(Informative.)* The [observability runbook Verify step](../operations/observability.md#verify) confirms the two S6a metrics in the collector's metric view after traffic is driven; running it alongside the span check confirms the whole telemetry pipeline at once.

### Related

- [TS-OBS-001](#ts-obs-001-no-spans-appear-at-the-collector) — no spans at the collector (shared endpoint/transport diagnosis).
- [Observability configuration reference §1, §4](../configuration/observability.md#1-scope) — the metric instruments and readers.
- [`RUN-OBSERVABILITY-001`](../operations/observability.md) — configure observability.
