# Configuration Reference: Provisioning API (`udr_provision`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the `udr_provision` application: the admin provisioning HTTP API that creates, reads, and deletes subscribers by [IMSI](../glossary.md). It documents the two configuration keys the application reads — the TCP port (`port`) and the bind address (`ip`).

The provisioning request and response contract (the subscriber payload and its fields) is out of scope here and belongs to the (planned) provisioning interface reference. That interface is where per-subscriber authentication data — algorithm, Ki, OP/OPc, [AMF (Authentication Management Field)](../glossary.md), and [SQN](../glossary.md) — is supplied; none of it is node configuration.

## 2. Terms

- **Provisioning listener** — the HTTP listener (`udr_provision_listener`) that serves `/provision/v1/subscribers/:imsi`.

## 3. Where configuration lives

Configuration is in `config/sys.config` under the `udr_provision` key, applied at boot. The shipped block is:

```erlang
{udr_provision, [{port, 8090}, {ip, {127,0,0,1}}]}
```

## 4. Parameter reference

| Parameter | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `port` | integer | `8090` | a TCP port number, `1`–`65535` | port | The TCP port the provisioning HTTP listener binds. | Sets the port an administrator connects to in order to provision subscribers. | 0.1.0 |
| `ip` | `ip4_address` (Erlang IPv4 tuple) | `{127,0,0,1}` | an IPv4 address tuple, e.g. `{0,0,0,0}` or `{10,0,0,5}` | — | The local address the provisioning HTTP listener binds. | Determines which network interface the provisioning API is reachable on. | 0.1.0 |

## 5. Parameter detail

### 5.1 `ip`

`ip` is an Erlang IPv4 address tuple.

- To provision from another host, `ip` `shall` be set to a routable address of this node, or to `{0,0,0,0}` to bind all interfaces.
- The default `{127,0,0,1}` binds loopback only; with the default, the provisioning API is reachable only from the node's own host.

> [!CAUTION]
> The provisioning API is unauthenticated. It performs no credential check on requests, and a caller that can reach the listener can create, read, and delete any subscriber — including the subscriber's permanent secret key material. Binding `ip` to a routable or wildcard address exposes full subscriber control to every host that can reach the port.

The following requirements follow from the API being unauthenticated:

- The provisioning listener `shall` be bound only to an interface reachable from a trusted management network; it `shall not` be bound to a public or untrusted interface.
- Where the provisioning API is bound to a non-loopback address, network-level access control (for example a firewall or a private management VLAN) `shall` restrict which hosts can reach `port`.
- Where provisioning is performed only from the node's own host, the default `{127,0,0,1}` `should` be kept.

### 5.2 `port`

- `port` `shall` be a free TCP port on the chosen `ip`; if another process holds the port, the listener fails to start at boot.

## 6. Example

```erlang
{udr_provision, [{port, 8090}, {ip, {192,168,10,4}}]}
```

This binds the provisioning API on `192.168.10.4:8090`, a management-network address reachable only from trusted operator hosts.

## 7. Verify

- From the node, confirm the listener is bound:

  ```sh
  ss -ltn '( sport = :8090 )'
  ```

  A socket `shall` be listed on the configured address.

- Confirm the listener answers HTTP. A `GET` for an unprovisioned subscriber returns `404`, which confirms the listener is up:

  ```sh
  curl -s -o /dev/null -w '%{http_code}\n' \
    http://127.0.0.1:8090/provision/v1/subscribers/001010000000001
  ```

  The expected status on a reachable node with no such subscriber is `404`.
