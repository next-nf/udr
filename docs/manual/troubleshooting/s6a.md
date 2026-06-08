# Troubleshooting: S6a Diameter (`udr_diameter`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers symptoms an operator observes on the [S6a](../glossary.md) [Diameter](../glossary.md) interface served by the `udr_diameter` application: an [MME](../glossary.md) that cannot establish a Diameter connection, the result codes the [AIR](../glossary.md), [ULR](../glossary.md), and [PUR](../glossary.md) procedures return on failure, an inbound command that draws no answer, and a [CLR](../glossary.md) that the previously registered MME never receives. The result codes referenced here are defined in the [S6a interface reference §7](../interfaces/s6a.md#7-status--result-codes); the listener configuration is defined in the [S6a Diameter configuration reference](../configuration/diameter.md).

---

## TS-S6A-001: An MME's CER is not answered; the peer never reaches the open state

### Symptom

An MME configured to connect to this HSS does not establish its Diameter session. The MME's `CER` (Capabilities-Exchange-Request) is not answered with a `CEA`, or the connection is never accepted at all, and the peer stays in a closed or connecting state. No `s6a.*` span and no `AIA`/`ULA` follow, because no peer is up.

### Affected component

`udr_diameter` — the S6a Diameter TCP listener.

### Likely causes

*(Ordered, most probable first.)*

1. The `listen` endpoint is bound to loopback (`{127,0,0,1}`), so the listener is unreachable from the MME's host. This is the shipped default.
2. The configured port is not reachable from the MME (a firewall or a wrong port on the MME side).
3. `origin_host` or `origin_realm` does not match what the MME is configured to expect, so the MME rejects the capabilities exchange.

### Diagnosis

1. Confirm the listener address and port on the node's host:
   ```sh
   ss -ltn '( sport = :3868 )'
   ```
   - Expected: a listening socket on the routable address configured in `udr_diameter` `listen`.
   - If it shows `127.0.0.1:3868`, the listener is bound to loopback and no off-host MME can reach it — cause 1.
   - If it shows nothing, no S6a listener is bound; confirm the node booted and the `udr_diameter` application started (see [`RUN-LIFECYCLE-001`](../operations/lifecycle.md)).
2. From the MME's host (or another host on the MME's network), test TCP reachability of the port:
   ```sh
   nc -vz <hss-address> 3868
   ```
   - Expected: the connection succeeds.
   - If it fails while Step 1 shows a socket on a routable address, the path is blocked between the hosts — cause 2.
3. Confirm the identity the node presents. From the node's console:
   ```erlang
   {application:get_env(udr_diameter, origin_host),
    application:get_env(udr_diameter, origin_realm)}.
   ```
   - Expected: the `origin_host` and `origin_realm` the MME is configured to expect for this HSS.
   - If either differs from the MME's configured peer identity or realm, the MME can reject the `CEA` — cause 3.

### Resolution

*(Normative.)*

- For cause 1: `listen` `shall` include an entry bound to a routable address reachable from the MME, per the [S6a Diameter configuration reference §5.3](../configuration/diameter.md#53-listen). When an external MME connects, an entry bound to `{127,0,0,1}` `shall not` be the only entry. The node `shall` be restarted for a `listen` change to take effect.
- For cause 2: the port in `listen` (standard S6a port `3868`) `shall` be reachable from the MME; network-level access control between the hosts `shall` permit it.
- For cause 3: `origin_host` and `origin_realm` `shall` match the identity and realm the MME is configured to expect, per the [configuration reference §5.1–§5.2](../configuration/diameter.md#51-origin_host).

### Prevention

*(Informative.)* Binding the listener and verifying `CER`/`CEA` is the procedure [`RUN-S6A-PEER-001`](../operations/s6a-peer.md); its Verify step confirms a `CEA` carrying the configured `origin_host` before an MME is brought into service.

### Related

- [S6a Diameter configuration reference](../configuration/diameter.md) — `listen`, `origin_host`, `origin_realm`.
- [S6a interface reference §3](../interfaces/s6a.md#3-transport-and-conventions) — transport, identity, and CER/CEA peer authentication.
- [`RUN-S6A-PEER-001`](../operations/s6a-peer.md) — connect and verify an MME.

---

## TS-S6A-002: An AIR is answered with USER_UNKNOWN (`5001`)

### Symptom

An MME's `AIR` for a subscriber is answered by an `AIA` that carries an `Experimental-Result` with Vendor-Id `10415` and Experimental-Result-Code `5001` (`DIAMETER_ERROR_USER_UNKNOWN`) instead of authentication vectors. The MME treats the subscriber as unknown and the attach fails. With a trace exporter configured, the `s6a.AIR` span carries attribute `s6a.result` = `user_unknown`.

### Affected component

`udr_diameter` (AIR path) and the data store behind it.

### Likely causes

*(Ordered, most probable first.)*

1. The subscriber's IMSI was never provisioned with an authentication subscription.
2. The subscriber was provisioned on an [ETS](../glossary.md)-backed node that has since restarted, so the in-memory data was discarded.
3. The IMSI in the `AIR` `User-Name` does not match the IMSI under which the subscriber was provisioned (for example a leading-zero or formatting difference).

### Diagnosis

1. Read the subscriber back over the provisioning API for the exact IMSI in the `User-Name`:
   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8090/provision/v1/subscribers/<imsi>
   ```
   - Expected for a provisioned subscriber: `200`.
   - If it returns `404`, no authentication subscription exists for that IMSI — cause 1 or cause 2.
2. Distinguish "never provisioned" from "lost on restart". Confirm the resolved backend at the node's console:
   ```erlang
   udr_db:backend().
   ```
   - Expected for a persistent deployment: `udr_db_mongo`.
   - If it is `udr_db_ets` and the subscriber was provisioned before the most recent restart, the data was discarded — cause 2. See [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart).
3. Confirm the IMSI matches. Compare the `User-Name` the MME sends (visible as the `s6a.imsi` span attribute when a trace exporter is configured) against the IMSI used at provisioning.
   - Expected: the two are byte-for-byte identical.
   - If they differ, the `AIR` addresses a different key than the one provisioned — cause 3.

### Resolution

*(Normative.)*

- For cause 1: the subscriber `shall` be provisioned with an `auth` object before the MME requests vectors, per [`RUN-PROVISION-001`](../operations/provisioning.md). A successful `PUT` returns `201`.
- For cause 2: where subscriber data is to survive a restart, the MongoDB backend `shall` be selected per the [data-store configuration reference §5.1](../configuration/data-store.md#51-backend); on an ETS node the subscriber `shall` be re-provisioned after each restart.
- For cause 3: the IMSI provisioned `shall` equal the IMSI the MME carries in `User-Name`.

### Prevention

*(Informative.)* The `AIR`-against-an-unprovisioned-IMSI case is documented as the expected `5001` path in the [S6a interface reference §8](../interfaces/s6a.md#8-verify); provisioning a known test IMSI and confirming an `AIA` with `Result-Code` = `2001` before service confirms the data path end to end.

### Related

- [S6a interface reference §5.1, §7](../interfaces/s6a.md#51-if-s6a-001--air--aia) — AIR detail and the `5001` code.
- [Provisioning interface reference](../interfaces/provisioning.md) and [`RUN-PROVISION-001`](../operations/provisioning.md).
- [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart) — data lost after restart.

---

## TS-S6A-003: An AIR is answered with UNABLE_TO_COMPLY (`5012`)

### Symptom

An MME's `AIR` for a **provisioned** subscriber is answered by an `AIA` carrying the base `Result-Code` AVP with `5012` (`DIAMETER_UNABLE_TO_COMPLY`) instead of vectors. Unlike `5001`, this happens for a subscriber the HSS knows. With a trace exporter configured, the `s6a.AIR` span does not carry `s6a.result` = `success`.

### Affected component

`udr_diameter` (AIR path), the HSS authentication logic (`udr_hss`), and the data store behind it.

### Likely causes

*(Ordered, most probable first.)*

1. The stored [SQN](../glossary.md) could not be advanced: the compare-and-set (CAS) update exhausted its retries, which a backend write that keeps failing under contention or a storage error can cause.
2. An AUTS resynchronization was requested (the `AIR` carried `Re-Synchronization-Info`) and the SQN repair failed.

### Diagnosis

1. Confirm the subscriber is provisioned (this distinguishes `5012` from `5001`):
   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8090/provision/v1/subscribers/<imsi>
   ```
   - Expected: `200`. A `5012` on a `404` subscriber would not occur; the path returns `5001` for an unprovisioned subscriber.
2. Confirm the data store is healthy, because a failing SQN write is the leading cause. For the MongoDB backend, at the node's console:
   ```erlang
   is_pid(udr_db_mongo_conn:conn()).
   ```
   - Expected: `true`.
   - If it raises or returns otherwise, the backend connection is down and writes are failing — see [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable). Resolve the data store first.
3. Determine whether the `AIR` was a resync. A resync `AIR` carries `Re-Synchronization-Info`; a plain attach `AIR` does not.
   - If the failing `AIR` is a resync, cause 2 applies: a resync whose MAC verifies repairs the SQN to `SQN_MS + 1`, and a repair that cannot be written returns `5012`.
   - If it is a plain `AIR`, cause 1 applies: the routine SQN advance exhausted its CAS retries.

### Resolution

*(Normative.)*

- For cause 1: the data store `shall` be confirmed healthy and reachable (see [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable)); once writes succeed, a retried `AIR` returns `2001`. Persistent CAS exhaustion under no contention indicates a backend write fault that `shall` be investigated against the data store.
- For cause 2: a resync that fails its SQN repair returns `5012` for that `AIR`; the UE `should` be allowed to retry, since fresh vectors are still generated on a subsequent `AIR` so the UE can resynchronize again.

> [!NOTE]
> A resync whose MAC does **not** verify is ignored, and the HSS still returns fresh vectors (not `5012`) so the UE can resync again. A `5012` from the resync path therefore indicates a failed SQN **write**, not a failed MAC check (confirmed in `udr_hss.erl`, `maybe_resync/5`).

### Prevention

*(Informative.)* `5012` from a provisioned subscriber points at the data store, not at provisioning. Keeping the MongoDB backend healthy (connection up, no write errors) avoids the CAS-exhaustion path; the data-store guide covers backend health.

### Related

- [S6a interface reference §5.1, §7](../interfaces/s6a.md#51-if-s6a-001--air--aia) — AIR resynchronization and the `5012` code.
- [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable) — MongoDB unreachable.

---

## TS-S6A-004: An inbound Diameter command draws no answer

### Symptom

The MME sends an S6a command and receives no answer at all — no error answer, no result code, no timeout-with-reply. The request appears to be silently dropped. The command is one **other** than `AIR`, `ULR`, or `PUR`.

### Affected component

`udr_diameter` — the request dispatcher (`udr_diameter_s6a:handle_request/3`).

### Likely causes

*(Ordered, most probable first.)*

1. The command is not one this node accepts as an inbound request. Only `AIR`, `ULR`, and `PUR` are handled; any other inbound command is discarded with no reply (confirmed in `handle_request/3`, the `discard` clause).
2. The MME is sending a command this HSS does not implement for the S6a application (for example IDR/IDA or DSR/DSA), expecting an answer the HSS never produces.

### Diagnosis

1. Identify the command the MME sent. Compare it against the accepted set.
   - Expected of an answered command: it is `AIR`, `ULR`, or `PUR`.
   - If it is any other command — including a `CLR` sent **to** this node — it is discarded; the peer sees no reply. This node originates `CLR` but does not accept an inbound one.
2. Distinguish "discarded command" from "malformed AIR/ULR/PUR". A malformed or missing-AVP `AIR`/`ULR`/`PUR` is **not** silently dropped — it draws an `answer_message` with `5005` (`DIAMETER_MISSING_AVP`).
   - Expected for a well-formed but unsupported command: no answer (the discard path).
   - If the MME instead received an answer with `5005` (`DIAMETER_MISSING_AVP`), the command was an `AIR`/`ULR`/`PUR` that failed decoding (a missing or malformed required AVP), not an unsupported command. That is a malformed request, handled by `handle_request/3`'s first clause, and is not the discard case.

### Resolution

*(Normative.)*

- For cause 1 and cause 2: the MME `should` be configured to send only the S6a commands this node implements — `AIR`, `ULR`, and `PUR`. An unsupported inbound command is by design discarded without a reply; no configuration on this node changes that. Where an MME requires a procedure this node does not implement, that requirement `shall` be raised against the system's supported feature set rather than treated as a misconfiguration.

> [!NOTE]
> The silent discard is intentional and is documented in the [S6a interface reference §7](../interfaces/s6a.md#7-status--result-codes): "An inbound command other than `AIR`, `ULR`, or `PUR` is silently discarded with no answer." The supported inbound commands are listed in [§4](../interfaces/s6a.md#4-operations).

### Prevention

*(Informative.)* Confirming which S6a commands the MME emits against the supported set in the interface reference, before integration, avoids an MME waiting on an answer the HSS will never send.

### Related

- [S6a interface reference §4, §7](../interfaces/s6a.md#4-operations) — the accepted inbound commands and the discard behavior.

---

## TS-S6A-005: A CLR is never received by the previously registered MME

### Symptom

A subscriber re-registers through a new MME (a `ULR` from a different MME than the one already registered). The old MME is expected to receive a `CLR` (Cancel-Location-Request) so it cancels the stale registration, but it never does. The `ULR` from the new MME still succeeds with a `ULA` (`Result-Code` = `2001`); only the cancellation at the old MME is missing.

### Affected component

`udr_diameter` — the HSS-initiated `CLR` effect (`udr_diameter_s6a:run_effect/1`).

### Likely causes

*(Ordered, most probable first.)*

1. This node has no routable Diameter connection to the previously registered MME's host and realm, so the `CLR` cannot be delivered. The `CLR` is sent fire-and-forget; a missing route raises no error on the `ULR` path.
2. The previously registered MME's `Origin-Host` / `Origin-Realm` (stored from its earlier `ULR`) do not resolve to a peer this node can reach, so the destination filter matches no connected peer.

### Diagnosis

1. Confirm the new `ULR` actually changed the serving MME. Read the registration over the SBI:
   ```sh
   curl -s http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-<imsi>/context-data/amf-3gpp-access
   ```
   - Expected: `200 OK` with `serving_mme_host` / `serving_mme_realm` equal to the **new** MME.
   - If the serving MME did not change (the new `ULR` came from the same MME already registered), no `CLR` is triggered — that is correct, not a fault. A `CLR` is originated only when the serving MME differs (confirmed in `udr_hss.erl`, `clr_effect_if_moved/2`).
2. Confirm this node has a connected Diameter peer matching the old MME's host and realm. The `CLR` is sent with a destination filter on `{host, OldHost}` and `{realm, OldRealm}`; if no connected peer matches, the call is dropped silently.
   - Expected: a Diameter connection to the old MME's host and realm exists and is up.
   - If no such peer is connected (the old MME is gone, unreachable, or never had a session to this HSS), the `CLR` cannot be delivered — cause 1 or cause 2.

### Resolution

*(Normative.)*

- For cause 1 and cause 2: where the old MME is to receive the `CLR`, a routable Diameter connection to its `Origin-Host` and `Origin-Realm` `shall` exist at the time the new `ULR` is processed. Diameter routing or peer configuration `shall` provide a path to the previously registered MME's host and realm.
- The `ULR` outcome `shall not` be treated as failed on account of an undelivered `CLR`: the `CLR` is fire-and-forget and its delivery does not gate the `ULA`.

> [!NOTE]
> Because the `CLR` is sent with `diameter:call(..., [detach])`, the matching `CLA` is absorbed and no result code from the old MME is surfaced to the operator (confirmed in `udr_diameter_s6a.erl`, `handle_answer/4`). There is therefore no positive operator-visible confirmation that the old MME processed the `CLR`; absence of delivery is not reported as an error. This is documented in the [S6a interface reference §5.4](../interfaces/s6a.md#54-if-s6a-004--clr--cla-hss-initiated).

### Prevention

*(Informative.)* A stale registration at an old MME is most often the consequence of that MME being unreachable from the HSS when the move occurs. Ensuring the HSS retains Diameter routes to the MMEs in its serving area keeps the `CLR` deliverable.

### Related

- [S6a interface reference §5.2, §5.4](../interfaces/s6a.md#52-if-s6a-002--ulr--ula) — the ULR-triggered CLR and its fire-and-forget delivery.
- [SBI interface reference §5.3](../interfaces/sbi.md#53-if-sbi-003--get-amf-3gpp-access) — reading the serving-node registration.
