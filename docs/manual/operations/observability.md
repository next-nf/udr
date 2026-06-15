# Operations Runbook: Configure Observability

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers pointing the node's [OpenTelemetry](../glossary.md) instrumentation at an [OTLP](../glossary.md) collector and confirming that spans and metrics arrive. It is for operators enabling traces and metrics export from the HSS. The OpenTelemetry parameters are defined in the [observability configuration reference](../configuration/observability.md); this runbook directs the operator through enabling export and does not repeat the parameter table.

---

## RUN-OBSERVABILITY-001: Export traces and metrics to an OTLP collector

### Purpose

*(Informative.)* With the shipped configuration the node produces spans and metrics internally but exports nothing (`traces_exporter` is `none`). This procedure switches the exporter on, points it at a collector, and confirms that an `s6a.AIR` span and the S6a metrics reach the collector. An operator runs it to bring the HSS under observability.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node is running, per [`RUN-LIFECYCLE-001`](lifecycle.md).
- An OTLP collector is reachable from the node, and the operator knows its endpoint URL and which OTLP transport it accepts (OTLP/HTTP on port `4318`, or OTLP/gRPC on port `4317`).
- A subscriber is provisioned and an S6a [AIR](../glossary.md) can be driven for it, so a span can be produced on demand (see [`RUN-PROVISION-001`](provisioning.md) and [`RUN-S6A-PEER-001`](s6a-peer.md)).

### Inputs and privileges

- The collector endpoint URL, for example `http://otel-collector.mgmt.example.net:4318`.
- The OTLP transport the collector accepts (`http_protobuf`, `grpc`, or `http_json`).
- Permission to edit `config/sys.config` and to restart the node.

### Steps

1. In `config/sys.config`, set `traces_exporter` to `otlp` and point the exporter at the collector. Set the `service.name` so the node is identifiable in the backend:

   ```erlang
   {opentelemetry, [
     {span_processor, batch},
     {traces_exporter, otlp},
     {resource, #{service => #{name => <<"hss-udr-prod-1">>}}}
   ]},
   {opentelemetry_exporter, [
     {otlp_protocol, http_protobuf},
     {otlp_endpoint, "http://otel-collector.mgmt.example.net:4318"}
   ]}
   ```

   The `otlp_protocol` `shall` match a transport the collector accepts (see the [observability configuration reference](../configuration/observability.md) §5.1).
2. Restart the node so the configuration is applied at boot, per [`RUN-LIFECYCLE-001`](lifecycle.md). (With the ETS backend, re-provision the test subscriber after the restart; see [`RUN-PROVISION-001`](provisioning.md).)
3. Drive one S6a AIR against the provisioned IMSI, from an external peer (see [`RUN-S6A-PEER-001`](s6a-peer.md)) or through the in-node AIR path shown in [quickstart.md](../quickstart.md) §6.2.

### Verify

*(Observable outcome.)*

- Confirm the exporter setting that resolved. From the node console (see [`RUN-LIFECYCLE-001`](lifecycle.md)):

  ```erlang
  application:get_env(opentelemetry, traces_exporter).
  ```

  The result `shall` be `{ok, otlp}`.

- After driving an AIR (Step 3), an `s6a.AIR` span `shall` appear in the collector for the configured `service.name`, carrying attribute `s6a.result` (for example `success` for a provisioned IMSI; `user_unknown` for an unprovisioned one). This is the observable confirmation that traces export end to end.

- The S6a metric instruments `s6a.requests` and `s6a.handler.duration` `shall` be reported through the configured metric reader (see the [observability configuration reference](../configuration/observability.md) §1, §4). Confirm they appear in the collector's metric view after driving traffic.

### Rollback / on failure

- If `application:get_env(opentelemetry, traces_exporter)` is `{ok, none}`, the change did not take effect; re-check `config/sys.config` and restart, per [`RUN-LIFECYCLE-001`](lifecycle.md).
- If no span reaches the collector, confirm the collector is reachable from the node at `otlp_endpoint`, that `otlp_protocol` matches the collector's accepted transport and port, and that an AIR was actually driven (an unprovisioned IMSI still produces a span, with `s6a.result` = `user_unknown`).
- To return to the shipped behavior, set `traces_exporter` back to `none` and restart; the node then produces spans internally but exports none, which is the safe default for a node with no collector.

### Related

- [Observability configuration reference](../configuration/observability.md) — the OpenTelemetry, exporter, and reader parameters.
- [Metrics reference](../../../METRICS.md) — the `s6a.requests` and `s6a.handler.duration` instruments and the Grafana dashboard.
- [`RUN-S6A-PEER-001`](s6a-peer.md) — drive an AIR to produce a span.
- [S6a interface reference](../interfaces/s6a.md) §8 — the `s6a.AIR` span and its `s6a.result` attribute.
