# Security Considerations and Hardening

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This document states the real security exposures of the `udr` HSS/UDR as it is built today, and the hardening an operator `shall` and `should` apply before running it outside a closed lab. Each exposure is grounded in the source. The hardening guidance uses the normative forms `shall` / `should` / `may`; the risks are flagged with admonitions.

Terms and abbreviations (HSS, UDR, SBI, Nudr, S6a, Diameter, MME, AMF, IMSI, Ki, OPc, TLS, TCP, HTTP, `epmd`, AGPL-3.0) are defined once in the [glossary](glossary.md) and are not redefined here.

> [!IMPORTANT]
> This document is informative as to the threat model and the rationale; the hardening statements are normative. It is not legal advice. The license note in §7 describes an operational obligation, not a legal opinion.

## 1. Threat model in one paragraph

The system holds the long-term secret authentication keys of every subscriber ([Ki](glossary.md) and [OPc](glossary.md)). Anyone who obtains those keys can clone a subscriber's identity and impersonate the network or the subscriber. The system serves three listeners, none of which encrypts its transport or, in two cases, authenticates its caller. The design assumes it runs on an isolated, trusted signaling network; it does not defend itself on an open network. The hardening below restores that assumption by network-level controls.

## 2. The exposures, grounded in the code

| ID | Exposure | Where | Confirmed in |
| --- | --- | --- | --- |
| `SEC-001` | Provisioning API is unauthenticated; any reachable caller can read and write every subscriber. | Provisioning listener, port `8090`. | `udr_api_app.erl` (`cowboy:start_clear`, no auth middleware); [interfaces/provisioning.md](interfaces/provisioning.md). |
| `SEC-002` | SBI returns long-term key material (Ki, OPc) in clear on the authentication-subscription resource. | SBI listener, port `8080`. | `udr_sbi.erl`, `auth_view/1` (hex-encodes `ki`/`opc`, no redaction); [interfaces/sbi.md §5.1](interfaces/sbi.md). |
| `SEC-003` | All transport is plaintext; no listener terminates TLS. | All three listeners. | `udr_sbi_app.erl` and `udr_api_app.erl` (`cowboy:start_clear`); `udr_diameter_srv.erl` (`diameter_tcp`, no TLS opts). |
| `SEC-004` | The Erlang distribution cookie is the cluster trust boundary; knowing it grants code execution on every node. | Erlang distribution between cluster nodes. | [configuration/cluster.md](configuration/cluster.md); [`RUN-SECRETS-001`](operations/secrets.md). |
| `SEC-005` | Secret material is stored and backed up in clear (Ki/OPc in the data store and in MongoDB backups). | `udr_db` store; backup archives. | [`RUN-SECRETS-001`](operations/secrets.md), [`RUN-BACKUP-001`](operations/backup-restore.md). |

## 3. Unauthenticated provisioning API (`SEC-001`)

The provisioning HTTP API on port `8090` performs no authentication. Its listener is started with `cowboy:start_clear` and a router that mounts the subscriber handler directly, with no authentication or authorization stream handler in front of it (confirmed in `udr_api_app.erl`). Any caller that can open a TCP connection to the listener can create, read, replace, and delete any subscriber by [IMSI](glossary.md), including writing arbitrary [Ki](glossary.md)/[OPc](glossary.md) values.

> [!CAUTION]
> A reachable provisioning port is a full read/write breach of the subscriber database. An attacker can enroll rogue subscribers, overwrite credentials, or delete the entire subscriber base.

Hardening:

- The provisioning listener `shall` be confined to a trusted management interface. The shipped default binds it to loopback `127.0.0.1:8090`, which exposes no port to the network; that default `shall not` be widened to a routable address unless an external control restricts who can reach it.
- Where remote provisioning is needed, an authenticating reverse proxy or a network policy that admits only the provisioning host `should` be placed in front of the listener; the listener `should not` be reachable directly from any subscriber-facing or peer-facing network.
- The bind address is set by the `ip` key of `udr_api`; see the [provisioning configuration reference](configuration/provisioning.md). The operational procedure is [`RUN-PROVISION-001`](operations/provisioning.md).

**Verify.** From a host that `should not` have provisioning access, a `curl` to `http://<node>:8090/provision/v1/subscribers/001010000000001` `shall` fail to connect (connection refused or timed out). A successful response from such a host indicates the listener is over-exposed.

## 4. Key material returned in clear over the SBI (`SEC-002`)

The SBI authentication-subscription resource returns the stored [Ki](glossary.md) and [OPc](glossary.md) hex-encoded in clear. The shaping function `auth_view/1` hex-encodes the `ki`, `opc`, and `amf` byte fields and returns them; it performs no redaction or omission (confirmed in `udr_sbi.erl`, `auth_view/1`). A `GET` on `/nudr-dr/v1/subscription-data/{ueId}/authentication-data/authentication-subscription` therefore discloses the long-term key material to any caller that reaches the SBI listener, which itself performs no caller authentication.

> [!CAUTION]
> This resource discloses the subscriber's permanent secret keys. Read access to the SBI is equivalent to read access to the credential store.

Hardening:

- The SBI listener `shall` be confined to a trusted signaling network reachable only by legitimate 5G consumers. The shipped default binds it to loopback `127.0.0.1:8080`.
- Access to the SBI `should` be mediated by a network policy or a service mesh that admits only known consumer network functions; the listener `should not` be reachable from a general-purpose or untrusted network.
- The bind address is set by the `ip` key of `udr_sbi`; see the [SBI configuration reference](configuration/sbi.md) and the [SBI interface reference](interfaces/sbi.md).

**Verify.** A `GET` on the authentication-subscription resource from a trusted consumer returns `200 OK` with `ki` and `opc` present in the body (confirmed in [quickstart.md §5.1](quickstart.md)). The same `GET` from an untrusted host `shall` fail to connect.

## 5. Plaintext transport on every listener (`SEC-003`)

No listener in this system terminates [TLS](glossary.md):

- The SBI listener and the provisioning listener are started with `cowboy:start_clear`, which serves cleartext [HTTP](glossary.md) with no TLS (confirmed in `udr_sbi_app.erl` and `udr_api_app.erl`). There is no `cowboy:start_tls` call anywhere in the source.
- The S6a [Diameter](glossary.md) listener is added with `transport_module` `diameter_tcp` and no TLS transport options (confirmed in `udr_diameter_srv.erl`, `add_listener/1`). Diameter therefore runs over plain [TCP](glossary.md).

The consequence is that subscriber identities, registration data, and — over the SBI — [Ki](glossary.md)/[OPc](glossary.md) cross the wire unencrypted, and a passive observer on the path can read them while an active one can modify them.

> [!WARNING]
> Because no listener encrypts its transport, confidentiality and integrity on every interface depend entirely on the network the system runs on. There is no in-application fallback.

Hardening:

- Every listener `shall` be deployed on an isolated signaling network that is not shared with untrusted hosts.
- Network-level controls `should` carry the confidentiality and integrity that the application does not: firewalling that admits only known peers, and where the traffic crosses an untrusted segment, an external transport-encryption layer (for example an IPsec tunnel or a TLS-terminating proxy or service mesh) `should` be placed around it.
- Listeners `should not` be bound to a routable address that any untrusted host can reach. The shipped loopback defaults are the safe starting point; widening a bind address is covered per listener in the [configuration references](configuration/README.md).

## 6. Erlang distribution and the cookie (`SEC-004`)

When the system is clustered, nodes trust one another through the Erlang distribution mechanism, gated by a shared distribution cookie. The cookie is the cluster's entire trust boundary: a host that knows the cookie and can reach a node's distribution port (and [`epmd`](glossary.md) on TCP `4369`) can connect as a peer node and run arbitrary code on every node in the mesh.

> [!CAUTION]
> A leaked distribution cookie is a remote-code-execution path onto every node. It is not merely a data-disclosure risk.

Hardening:

- The distribution cookie `shall` be treated as a secret. The shipped `udr_cookie` value `shall` be replaced before any cluster is formed across hosts.
- Erlang distribution and [`epmd`](glossary.md) `shall` be confined to a trusted network; the distribution port range and `epmd` `shall not` be reachable from any untrusted host.
- The cookie is set by `-setcookie` in `config/vm.args`; see the [node configuration reference](configuration/node.md) and the [cluster configuration reference](configuration/cluster.md). Handling the cookie as a secret is part of [`RUN-SECRETS-001`](operations/secrets.md).

**Verify.** From an untrusted host, a TCP connection to the node's `epmd` port `4369` `shall` fail. A node started with a non-default cookie `shall not` interconnect with a node that still uses the shipped cookie (`nodes()` does not list it); see the [cluster troubleshooting guide](troubleshooting/cluster.md).

## 7. Secret material at rest (`SEC-005`)

The long-term keys are stored and backed up in clear:

- In the `udr_db` store, the authentication subscription holds `ki` and `opc` as byte fields. The store applies no encryption of its own.
- A [MongoDB](glossary.md) backup archive contains every subscriber's `ki` and `opc`. A backup is therefore as sensitive as the live store.

Hardening:

- The data store and every backup archive `shall` be protected as secret material, with the same access restriction as the live credentials.
- Disk-level or database-level encryption at rest `should` be applied where the deployment's threat model requires confidentiality of the store on disk.
- The procedures for handling secret material and for protecting backups are [`RUN-SECRETS-001`](operations/secrets.md) and [`RUN-BACKUP-001`](operations/backup-restore.md). They are the authoritative source; this section only states the exposure.

## 8. License obligation (operational relevance)

This system is distributed under the [AGPL-3.0](glossary.md) (see the `LICENSE` file at the repository root). The AGPL-3.0 adds a network-use obligation to the GPL: an operator who **modifies** the software and then **offers it as a service over a network** is obliged to make the corresponding modified source available to the users interacting with it over that network.

> [!NOTE]
> This note flags an operational and compliance consideration, not a legal opinion. An operator who runs the unmodified release has no source-distribution obligation arising from operation alone. An operator who modifies the code and exposes the modified service to remote users `should` plan to publish the modified source to those users, and `should` seek qualified legal advice on the specifics. The license text in `LICENSE` governs.

## 9. Hardening checklist

Before exposing the system beyond a closed lab, confirm each item:

- [ ] The provisioning listener (`8090`) is bound to a trusted management interface only (`SEC-001`).
- [ ] The SBI listener (`8080`) is reachable only by legitimate 5G consumers (`SEC-002`).
- [ ] The S6a listener (`3868`) is reachable only by legitimate MMEs (`SEC-002`/`SEC-003`).
- [ ] Every interface that crosses an untrusted segment is wrapped by an external transport-encryption layer (`SEC-003`).
- [ ] The shipped distribution cookie has been replaced and distribution/`epmd` are network-confined (`SEC-004`).
- [ ] The data store and all backups are access-restricted as secret material (`SEC-005`).
- [ ] If the code is modified and offered as a network service, the AGPL-3.0 source obligation is planned for (§8).

## 10. Related documents

- [interfaces/provisioning.md](interfaces/provisioning.md) and [interfaces/sbi.md](interfaces/sbi.md) — the interface contracts behind `SEC-001` and `SEC-002`.
- [configuration/provisioning.md](configuration/provisioning.md), [configuration/sbi.md](configuration/sbi.md), [configuration/diameter.md](configuration/diameter.md) — the bind-address keys for confining each listener.
- [configuration/node.md](configuration/node.md) and [configuration/cluster.md](configuration/cluster.md) — the distribution cookie and clustering prerequisites.
- [operations/secrets.md](operations/secrets.md) (`RUN-SECRETS-001`) and [operations/backup-restore.md](operations/backup-restore.md) (`RUN-BACKUP-001`) — handling secret material and backups.
- [diagrams/README.md](diagrams/README.md) — the deployment diagrams that mark these exposures.
