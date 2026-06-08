# Configuration Reference: S6a Diameter (`udr_diameter`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the `udr_diameter` application: the [S6a](../glossary.md) [Diameter](../glossary.md) wire layer and its TCP listener. It documents the Diameter identity this node presents (`origin_host`, `origin_realm`) and the transport endpoints it binds (`listen`).

The S6a message contract (AIR/AIA, ULR/ULA, PUR/PUA, CLR/CLA) is out of scope here and belongs to the (planned) S6a interface reference. Node name and distribution cookie are covered in the [node reference](node.md).

## 2. Terms

- **Origin-Host** — the DiameterIdentity AVP this node presents to peers in every Diameter message. See [AVP](../glossary.md).
- **Origin-Realm** — the Diameter realm this node belongs to, presented in the Origin-Realm AVP.
- **Listener** — a bound TCP endpoint on which the node accepts Diameter connections from an [MME](../glossary.md).

## 3. Where configuration lives

Configuration is in `config/sys.config` under the `udr_diameter` key, applied at boot. The shipped block is:

```erlang
{udr_diameter, [
  {origin_host, "hss.epc.mnc001.mcc001.3gppnetwork.org"},
  {origin_realm, "epc.mnc001.mcc001.3gppnetwork.org"},
  {listen, [{tcp, {127,0,0,1}, 3868}]}
]}
```

> [!NOTE]
> `udr_diameter_srv` reads these keys with the in-code defaults shown in the table below (`"hss.local"`, `"local"`, `[{tcp,{127,0,0,1},3868}]`). The shipped `config/sys.config` overrides `origin_host` and `origin_realm` with the realistic 3GPP values above. If the `udr_diameter` block were removed entirely, the in-code defaults would apply.

## 4. Parameter reference

| Parameter | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `origin_host` | string | `"hss.local"` (in-code); shipped `sys.config` sets `"hss.epc.mnc001.mcc001.3gppnetwork.org"` | a DiameterIdentity (typically an FQDN) | — | The Origin-Host identity this node presents to Diameter peers. | A peer matches this against its configured Destination-Host / expected Origin-Host; a mismatch can cause the peer to reject the connection. | 0.1.0 |
| `origin_realm` | string | `"local"` (in-code); shipped `sys.config` sets `"epc.mnc001.mcc001.3gppnetwork.org"` | a Diameter realm (typically an FQDN) | — | The Origin-Realm this node belongs to. | Used by peers for realm-based routing of S6a messages. | 0.1.0 |
| `listen` | list of `{tcp, IpV4, Port}` | `[{tcp, {127,0,0,1}, 3868}]` | one or more `{tcp, IpV4Address, Port}` tuples | port | The transport endpoints the S6a Diameter listener binds. | Determines which addresses and ports an MME can connect to. | 0.1.0 |

## 5. Parameter detail

### 5.1 `origin_host`

`origin_host` is the identity carried in every Diameter message this node sends, including the CEA answering a peer's CER.

- `origin_host` `should` be a fully-qualified domain name within the operator's realm.
- The value `shall` match what the MME peer is configured to expect as this node's host; otherwise the peer can reject the connection or its answers.

### 5.2 `origin_realm`

- `origin_realm` `should` be the operator's Diameter realm and `should` be the domain suffix of `origin_host`.

### 5.3 `listen`

`listen` is a list of transport endpoints. Each entry is `{tcp, IpV4Address, Port}`, where `IpV4Address` is an Erlang IPv4 tuple such as `{10,0,0,5}` and `Port` is a TCP port number.

- When an MME on a separate host connects, `listen` `shall` include an entry bound to a routable address; an entry bound to `{127,0,0,1}` `shall not` be the only entry.
- The standard S6a Diameter port is `3868`; a non-standard port `may` be used where the MME peer is configured to match.
- `listen` `may` contain more than one entry to bind several addresses or ports; the listener binds each entry in turn.

> [!WARNING]
> The default `{tcp, {127,0,0,1}, 3868}` binds the S6a listener to loopback only. A fresh checkout therefore exposes no Diameter port to the network and no external MME can connect. To accept an external MME, change `listen` to a routable address.

> [!NOTE]
> The default binds to loopback so a fresh checkout is safe by default and exposes no Diameter port.

## 6. Example

```erlang
{udr_diameter, [
  {origin_host, "hss01.epc.mnc001.mcc001.3gppnetwork.org"},
  {origin_realm, "epc.mnc001.mcc001.3gppnetwork.org"},
  {listen, [{tcp, {10,0,0,5}, 3868}]}
]}
```

This binds the S6a listener on `10.0.0.5:3868` and presents `hss01.epc.mnc001.mcc001.3gppnetwork.org` so an external MME in the same realm can connect.

## 7. Verify

- From the node, confirm the listener is bound on the configured address and port:

  ```sh
  ss -ltn '( sport = :3868 )'
  ```

  A socket `shall` be listed on the configured address (`127.0.0.1` with the shipped default, or the routable address you set).

- A peer's CER `shall` be answered with a CEA carrying the configured `origin_host` in its Origin-Host AVP.

- An AIR against a provisioned [IMSI](../glossary.md) produces an `s6a.AIR` [OpenTelemetry](../glossary.md) span when a trace exporter is configured (see the [observability reference](observability.md)).
