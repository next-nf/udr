# Configuration Reference: SBI (Nudr-DR) Listener (`udr_sbi`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the `udr_sbi` application: the [Nudr](../glossary.md)-flavoured 5G [SBI](../glossary.md) data-repository HTTP listener. It documents the two configuration keys the application reads — the TCP port (`port`) and the bind address (`ip`).

The Nudr-DR resource contract (the `authentication-subscription`, `am-data`, and `amf-3gpp-access` resources) is out of scope here and belongs to the [SBI interface reference](../interfaces/sbi.md).

## 2. Terms

- **SBI listener** — the HTTP listener (`udr_sbi_listener`) that serves the Nudr-DR resources under `/nudr-dr/v1/subscription-data`.

## 3. Where configuration lives

Configuration is in `config/sys.config` under the `udr_sbi` key, applied at boot. The shipped block is:

```erlang
{udr_sbi, [{port, 8080}, {ip, {127,0,0,1}}]}
```

## 4. Parameter reference

| Parameter | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `port` | integer | `8080` | a TCP port number, `1`–`65535` | port | The TCP port the SBI HTTP listener binds. | Sets the port a 5G consumer (for example the [AMF](../glossary.md)) connects to for Nudr-DR. | 0.1.0 |
| `ip` | `ip4_address` (Erlang IPv4 tuple) | `{127,0,0,1}` | an IPv4 address tuple, e.g. `{0,0,0,0}` or `{10,0,0,5}` | — | The local address the SBI HTTP listener binds. | Determines which network interface the SBI is reachable on. | 0.1.0 |

## 5. Parameter detail

### 5.1 `ip`

`ip` is an Erlang IPv4 address tuple, such as `{127,0,0,1}` or `{0,0,0,0}`.

- To accept SBI connections from a consumer on another host, `ip` `shall` be set to a routable address of this node, or to `{0,0,0,0}` to bind all interfaces.
- The default `{127,0,0,1}` binds loopback only; with the default, no off-host consumer can reach the SBI.

> [!NOTE]
> The default binds to loopback so a fresh checkout exposes no SBI port to the network.

### 5.2 `port`

- `port` `shall` be a free TCP port on the chosen `ip`; if another process holds the port, the listener fails to start at boot.
- A non-default port `may` be used where the consumer is configured to match.

## 6. Example

```erlang
{udr_sbi, [{port, 8080}, {ip, {10,0,0,5}}]}
```

This binds the SBI listener on `10.0.0.5:8080` so a 5G consumer on the same network can reach the Nudr-DR resources.

## 7. Verify

- From the node, confirm the listener is bound:

  ```sh
  ss -ltn '( sport = :8080 )'
  ```

  A socket `shall` be listed on the configured address.

- Confirm the listener answers HTTP. A `GET` for an unprovisioned subscriber returns `404`, which confirms the listener is up:

  ```sh
  curl -s -o /dev/null -w '%{http_code}\n' \
    http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/provisioned-data/am-data
  ```

  The expected status on a reachable node with no such subscriber is `404`.
