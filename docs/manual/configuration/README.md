# Configuration Reference

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This directory holds one configuration reference per subsystem of the `udr` project. Each reference documents the configuration parameters of one [OTP application](../glossary.md) (or, for the node reference, the release and the [BEAM](../glossary.md) node itself): the parameter's type, default, allowed values, effect, and an observable way to confirm it took effect.

This index is informative. The references it links to carry the normative parameter definitions.

## 1. Where configuration lives

Two files hold all shipped configuration:

| File | Holds | Applied |
| --- | --- | --- |
| `config/sys.config` | Application environment for every OTP application (the per-application key blocks). | At node boot. |
| `config/vm.args` | Node-level [BEAM](../glossary.md) arguments: node name, distribution cookie, and emulator flags. | At node start, before any application boots. |

> [!NOTE]
> `config/sys.config` is the standard Erlang/OTP system configuration file. Each top-level tuple is `{ApplicationName, [{Key, Value}, ...]}`. A key absent from the file takes the default documented in the matching reference below; a key present in the file overrides that default.

## 2. References

| Reference | Application(s) | Covers |
| --- | --- | --- |
| [Node and release](node.md) | the release / BEAM node | `config/vm.args` (`-sname`/`-name`, `-setcookie`, `+K`, `+A`) and the relx `dev`/`prod` release modes. |
| [S6a Diameter](diameter.md) | `udr_diameter` | `origin_host`, `origin_realm`, `listen`. |
| [SBI (Nudr-DR)](sbi.md) | `udr_sbi` | `port`, `ip`. |
| [Provisioning API](provisioning.md) | `udr_provision` | `port`, `ip`. |
| [Data store](data-store.md) | `udr_db`, `udr_db_mongo` | `backend`, `backend_opts`, and the MongoDB connection options. |
| [Observability](observability.md) | `opentelemetry`, `opentelemetry_exporter`, `opentelemetry_experimental`, `udr_otel` | Span processor, trace exporter, resource, OTLP transport, metric readers. |
| [Cluster](cluster.md) | `udr_cluster` | Per-[IMSI](../glossary.md) session locking and its node-distribution prerequisites. |

## 3. Applications with no configuration of their own

The following applications read no application environment and expose no operator-tunable key. They are listed here so that their absence from the references above is explicit, not an omission.

| Application | Note |
| --- | --- |
| `udr_crypto` | Reads no environment. The authentication algorithm ([MILENAGE](../glossary.md)) is selected per subscriber from the `algorithm` field of the provisioned authentication subscription, not by global configuration. See the provisioning interface. |
| `udr_data` | Reads no environment. It is the data-access seam over `udr_db`. |
| `udr_hss` | Reads no environment. It consumes `udr_diameter`, `udr_data`, and `udr_cluster`. |
| `udr` | The top-level release application. Its `sys.config` block is empty. |

> [!NOTE]
> The per-subscriber authentication algorithm, Ki, OP/OPc, [AMF (Authentication Management Field)](../glossary.md), and [SQN](../glossary.md) are provisioned through the [provisioning API](provisioning.md), not set in `config/sys.config`. They are subscriber data, not node configuration.
