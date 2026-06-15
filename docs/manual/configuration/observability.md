# Configuration Reference: Observability (OpenTelemetry)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-15

## 1. Scope

This reference covers the [OpenTelemetry](../glossary.md) configuration the node reads: the `opentelemetry`, `opentelemetry_exporter`, and `opentelemetry_experimental` application keys in `config/sys.config`, which configure span processing, the trace exporter, the resource, the [OTLP](../glossary.md) transport, and the metric readers.

The `udr_otel` application creates the S6a metric instruments (`s6a.requests`, `s6a.handler.duration`) at start and, via `setup_instrumentation/0`, registers the instruments of the OpenTelemetry instrumentation libraries the node runs: HTTP server metrics (`opentelemetry_cowboy_h`), Diameter stack metrics (`opentelemetry_diameter`), and BEAM/VM and process metrics (`opentelemetry_beam`, `opentelemetry_process`). None of these reads an application environment of its own or has an operator-tunable key. All of them report under whatever reader the `opentelemetry_experimental` key configures. The instruments themselves — their types, units, attributes, and the Grafana dashboard — are catalogued in the [metrics reference](../../../METRICS.md); this reference covers only the configuration that collects and exports them.

These keys belong to the OpenTelemetry Erlang libraries, not to this project. Only the keys present in the shipped `config/sys.config` are documented here; each library exposes further keys that are out of scope.

## 2. Terms

- **Span processor** — the component that batches or directly forwards completed spans to the exporter.
- **Trace exporter** — the component that emits spans to a destination (a collector, or nowhere).
- **Resource** — the set of attributes (such as the service name) attached to every span and metric from this node.
- **Metric reader** — the component that collects recorded metrics and makes them available to an exporter.

## 3. Where configuration lives

Configuration is in `config/sys.config`, applied at boot. The shipped blocks are:

```erlang
{opentelemetry, [
  {span_processor, batch},
  {traces_exporter, none},
  {resource, #{service => #{name => <<"hss-udr">>}}}
]},
{opentelemetry_exporter, [
  {otlp_protocol, http_protobuf},
  {otlp_endpoint, "http://localhost:4318"}
]},
{opentelemetry_experimental, [
  {readers, [
    %% OTLP push (native OTEL); a collector (e.g. Grafana Alloy) converts to Prometheus.
    #{module => otel_metric_reader, config => #{}},
    %% In-process OTEL Prometheus exporter; udr_otel serves it at GET :9464/metrics.
    #{module => otel_metric_reader_prometheus,
      config => #{server_name => udr_prometheus_reader,
                  add_total_suffix => true, add_scope_info => false}}
  ]}
]},
{udr_otel, [{metrics_port, 9464}, {metrics_ip, {127,0,0,1}}]}
```

> [!NOTE]
> With the shipped configuration, `traces_exporter` is `none`: spans are produced internally but exported nowhere. The `opentelemetry_exporter` block is present so that switching `traces_exporter` to `otlp` needs only that one change; on its own it exports nothing. Metrics, by contrast, are always available at `:9464/metrics` (the Prometheus reader) regardless of the trace exporter.

## 4. Parameter reference

| Parameter | App | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `span_processor` | `opentelemetry` | atom | `batch` | `batch`, `simple` | — | How completed spans are handed to the exporter. | `batch` buffers and exports spans in batches; `simple` exports each span as it completes. | 0.1.0 |
| `traces_exporter` | `opentelemetry` | atom | `none` | `none`, `otlp` | — | The span exporter. | `none` exports no spans; `otlp` exports over OTLP using the `opentelemetry_exporter` settings. | 0.1.0 |
| `resource` | `opentelemetry` | map | `#{service => #{name => <<"hss-udr">>}}` | a resource attribute map | — | Attributes attached to every span and metric from this node. | Sets the `service.name` (and any further attributes) a backend uses to identify this node. | 0.1.0 |
| `otlp_protocol` | `opentelemetry_exporter` | atom | `http_protobuf` | `http_protobuf`, `grpc`, `http_json` | — | The OTLP wire transport the exporter uses. | Selects how spans and metrics are encoded and sent to the collector. | 0.1.0 |
| `otlp_endpoint` | `opentelemetry_exporter` | string (URL) | `"http://localhost:4318"` | an OTLP collector endpoint URL | — | The collector endpoint the exporter sends to. | Sets where exported spans and metrics are delivered. | 0.1.0 |
| `readers` | `opentelemetry_experimental` | list of maps | the OTLP reader plus the Prometheus reader (see §3) | one or more reader specifications | — | The metric readers that collect recorded instruments. | Each reader independently collects and exports all instruments. The shipped pair gives an OTLP push reader and the in-process Prometheus reader behind `:9464/metrics`. | 0.1.0 |
| `metrics_port` | `udr_otel` | integer | `9464` | a TCP port | — | The port the OTEL Prometheus `/metrics` endpoint listens on. | Sets where the in-process Prometheus exporter is scraped. A bind failure is logged, not fatal. | 0.1.0 |
| `metrics_ip` | `udr_otel` | tuple | `{127,0,0,1}` | an IPv4/IPv6 address tuple | — | The address the `/metrics` endpoint binds. | `{127,0,0,1}` keeps the endpoint host-local; the container config uses `{0,0,0,0}` so it is scrapable from outside the container. | 0.1.0 |

## 5. Parameter detail

### 5.1 `traces_exporter` and the OTLP endpoint

`traces_exporter` gates whether spans leave the node.

- To export spans to a collector, `traces_exporter` `shall` be set to `otlp`, and `otlp_endpoint` `shall` point to a reachable OTLP collector.
- When `traces_exporter` is `none`, `otlp_protocol` and `otlp_endpoint` have no effect, because nothing is exported.
- `otlp_protocol` `shall` match a transport the configured collector accepts; `http_protobuf` corresponds to the default OTLP/HTTP port `4318`, and `grpc` to the default OTLP/gRPC port `4317`.

> [!TIP]
> Keeping `traces_exporter` at `none` is appropriate for a node with no collector; the instrumentation imposes negligible cost when nothing is exported. Set it to `otlp` only when a collector is available at `otlp_endpoint`.

### 5.2 `span_processor`

- The default `batch` processor `should` be kept in production, because it amortizes export cost across many spans.
- `simple` `may` be used in development to export each span immediately, at higher per-span overhead.

### 5.3 `resource`

- `resource` `should` carry a `service.name` that uniquely identifies this node in the observability backend; the shipped value is `<<"hss-udr">>`.

## 6. Example

Export traces to a local OTLP/HTTP collector and label the node:

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

This exports spans (for example `s6a.AIR`) over OTLP/HTTP to the named collector, identifying the node as `hss-udr-prod-1`.

## 7. Verify

- Confirm the exporter setting that resolved. From the running Erlang shell:

  ```erlang
  application:get_env(opentelemetry, traces_exporter).
  ```

  The result `shall` be `{ok, none}` with the shipped configuration, or `{ok, otlp}` once export is enabled.

- With `traces_exporter` set to `otlp` and a collector at `otlp_endpoint`, drive one S6a AIR against a provisioned [IMSI](../glossary.md); an `s6a.AIR` span `shall` appear in the collector. With `traces_exporter` at `none`, no span reaches any collector, which is the expected shipped behavior.

- Confirm the Prometheus `/metrics` endpoint. With the node running:

  ```sh
  curl -s http://127.0.0.1:9464/metrics | head
  ```

  The response `shall` be a Prometheus text exposition (HTTP `200`). After driving traffic, the series `s6a_requests_total` and `http_server_request_duration_seconds_bucket` `shall` be present. Metric series names and the OTEL→Prometheus transform are catalogued in the [metrics reference](../../../METRICS.md) §6.
