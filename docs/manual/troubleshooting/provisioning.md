# Troubleshooting: Provisioning API (`udr_provision`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers symptoms an operator observes on the admin provisioning HTTP API served by the `udr_provision` application: a `400` from request-body validation, a `404` on a read or delete of an unknown subscriber, a `500` when storage fails, and the inability to reach the listener at all. The status codes and error bodies referenced here are defined in the [provisioning interface reference §7](../interfaces/provisioning.md#7-status--result-codes); the listener configuration is defined in the [provisioning configuration reference](../configuration/provisioning.md).

> [!NOTE]
> Provisioning error bodies are `application/json` of the form `{"error":"<message>"}` (not `application/problem+json`). The `<message>` strings quoted below are the exact values the handler returns.

---

## TS-PROV-001: A PUT returns `400` from body validation

### Symptom

A `PUT /provision/v1/subscribers/{imsi}` returns `400 Bad Request` with a JSON body `{"error":"<message>"}`. The subscriber is not created. The exact `<message>` identifies which validation failed.

### Affected component

`udr_provision` — `udr_provision_subscriber_h` (the `PUT` clause) and `udr_provision_subscriber:auth_from_json/1`.

### Likely causes

*(Ordered, most probable first.)*

The `<message>` in the body distinguishes the cause directly:

1. `{"error":"missing 'auth' object"}` — the body is not a JSON object, or it has no top-level `auth` object.
2. `{"error":"auth requires 'opc' or 'op' (and 'ki','amf')"}` — the `auth` object supplies neither `opc` nor `op` (a `badarg` raised while deriving OPc).
3. `{"error":"invalid request body"}` — a catch-all for any other malformed `auth`: a missing `ki` or `amf`, an `auth.algorithm` other than `"milenage"`, or a hex field that does not decode to bytes.

### Diagnosis

1. Read the `error` message in the `400` body; it names the failure class. Match it to one of the three causes above.
2. For cause 1, confirm the body is a JSON object with a top-level `auth` key:
   ```sh
   curl -s -X PUT -H 'content-type: application/json' \
     -d '{"auth":{"ki":"465b5ce8b199b49faa5f0a2ee238a6bc","opc":"cd63cb71954a9f4e48a5994e37a02baf","amf":"8000"}}' \
     http://127.0.0.1:8090/provision/v1/subscribers/001010000000001
   ```
   - Expected for a well-formed body: `201` with `{"imsi":"001010000000001","status":"provisioned"}`.
   - If the original body had no `auth` key (for example the credentials were sent at the top level), it returns `{"error":"missing 'auth' object"}` — cause 1.
3. For cause 2, confirm the `auth` object carries exactly one of `opc` or `op` (together with `ki` and `amf`). Neither present is the `badarg` case.
   - Expected: `opc` present (used directly), or `op` present (OPc derived from `op` and `ki` at provisioning time).
   - If neither is present, cause 2 applies.
4. For cause 3, confirm `ki` and `amf` are present and that every hex field is valid lowercase/uppercase hexadecimal of the expected byte length, and that `algorithm`, if present, is `"milenage"`.
   - Expected: `ki` and `amf` present; `algorithm` absent (defaults to `"milenage"`) or exactly `"milenage"`.
   - A missing `ki`/`amf`, an unknown `algorithm`, or a hex string that does not decode falls into the `{"error":"invalid request body"}` catch-all — cause 3.

### Resolution

*(Normative.)*

- The `PUT` body `shall` be a JSON object containing an `auth` object, per the [provisioning interface reference §5.1](../interfaces/provisioning.md#51-if-prov-001--put-subscriber).
- The `auth` object `shall` contain `ki` and `amf`, and `shall` contain at least one of `opc` or `op`.
- Where `algorithm` is supplied it `shall` be `"milenage"`; any other value is rejected. When absent it defaults to `"milenage"`.
- Each hex field (`ki`, `amf`, and `opc` or `op`) `shall` be valid hexadecimal of the length the algorithm expects.

### Prevention

*(Informative.)* The [provisioning interface reference §5.1](../interfaces/provisioning.md#51-if-prov-001--put-subscriber) gives the full body schema and an example exchange; the [provisioning runbook `RUN-PROVISION-001`](../operations/provisioning.md) provides a known-good `PUT` to copy. The [interface reference §8](../interfaces/provisioning.md#8-verify) includes the exact "neither `opc` nor `op`" `400` as a validation check.

### Related

- [Provisioning interface reference §5.1, §7](../interfaces/provisioning.md#51-if-prov-001--put-subscriber) — the body schema and validation.
- [`RUN-PROVISION-001`](../operations/provisioning.md) — provision a subscriber.

---

## TS-PROV-002: A GET returns `404` "subscriber not found"

### Symptom

A `GET /provision/v1/subscribers/{imsi}` returns `404 Not Found` with body `{"error":"subscriber not found"}` for a subscriber the operator expected to find.

### Affected component

`udr_provision` — `udr_provision_subscriber_h` (the `GET` clause) over the data store.

### Likely causes

*(Ordered, most probable first.)*

1. No authentication subscription exists for that `{imsi}`: it was never provisioned, or a prior `PUT` was rejected with a `400` (see [TS-PROV-001](#ts-prov-001-a-put-returns-400-from-body-validation)) and never stored.
2. The `{imsi}` in the path does not match the IMSI under which the subscriber was provisioned. The provisioning path takes the IMSI verbatim with **no** `imsi-` prefix and no format check, so a stray prefix or a formatting difference addresses a different key.
3. The subscriber was provisioned on an [ETS](../glossary.md)-backed node that has since restarted, discarding the in-memory data.

### Diagnosis

1. Confirm the path uses the bare IMSI, not the SBI `imsi-<digits>` form. The provisioning resource is `/provision/v1/subscribers/{imsi}` with `{imsi}` taken verbatim.
   - Expected: `/provision/v1/subscribers/001010000000001`.
   - If the path includes an `imsi-` prefix, it addresses a key literally named `imsi-001010000000001`, distinct from the provisioned key — cause 2.
2. Confirm the resolved backend at the node's console:
   ```erlang
   udr_db:backend().
   ```
   - Expected for a persistent deployment: `udr_db_mongo`.
   - If it is `udr_db_ets` and the subscriber was provisioned before the most recent restart, the data was discarded — cause 3.
3. Re-provision a known test subscriber and read it straight back to confirm the round trip works at all:
   ```sh
   curl -s -X PUT -H 'content-type: application/json' \
     -d '{"auth":{"ki":"465b5ce8b199b49faa5f0a2ee238a6bc","opc":"cd63cb71954a9f4e48a5994e37a02baf","amf":"8000"}}' \
     http://127.0.0.1:8090/provision/v1/subscribers/001010000000099
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8090/provision/v1/subscribers/001010000000099
   ```
   - Expected: the `PUT` returns `201` and the `GET` returns `200`. If so, the API and storage round-trip works and the original `404` was a missing or mis-keyed subscriber — cause 1 or cause 2.

### Resolution

*(Normative.)*

- For cause 1: the subscriber `shall` be provisioned with a `PUT` that returns `201` before it can be read. A prior `400` means nothing was stored; resolve the `400` per [TS-PROV-001](#ts-prov-001-a-put-returns-400-from-body-validation).
- For cause 2: the `{imsi}` used on `GET` `shall` equal the `{imsi}` used on the `PUT` exactly, with no `imsi-` prefix.
- For cause 3: where data is to survive a restart, the MongoDB backend `shall` be selected per the [data-store configuration reference §5.1](../configuration/data-store.md#51-backend). See [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart).

> [!NOTE]
> A `DELETE` on an unknown IMSI does **not** return `404`; it returns `204` and is idempotent (confirmed in `udr_provision_subscriber_h.erl`). The `404` "subscriber not found" arises only on `GET`.

### Prevention

*(Informative.)* The provisioning [Verify step §8](../interfaces/provisioning.md#8-verify) uses a `404` for an unprovisioned subscriber to confirm the listener is reachable; a `404` therefore confirms reachability, and the question is only whether the IMSI and backend are right.

### Related

- [Provisioning interface reference §5.2, §7](../interfaces/provisioning.md#52-if-prov-002--get-subscriber) — the read and the `404`.
- [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart) — data lost after restart.

---

## TS-PROV-003: A PUT returns `500` "storage error"

### Symptom

A `PUT /provision/v1/subscribers/{imsi}` whose body validated returns `500 Internal Server Error` with body `{"error":"storage error"}`. The body was well-formed (it did not draw a `400`), but the subscriber could not be stored.

### Affected component

`udr_provision` — `udr_provision_subscriber_h` (`store/3`) over the data store.

### Likely causes

*(Ordered, most probable first.)*

1. The configured data backend failed the write. For the MongoDB backend, the connection is down or the database is unreachable; `udr_data:put_*` returns `{error, _}`, which the handler maps to `500`.
2. The MongoDB server is reachable but rejecting the write (an authentication failure or insufficient permission on the configured database).

### Diagnosis

1. Confirm the resolved backend and, for MongoDB, the connection. At the node's console:
   ```erlang
   {udr_db:backend(), catch is_pid(udr_db_mongo_conn:conn())}.
   ```
   - Expected for a healthy MongoDB deployment: `{udr_db_mongo, true}`.
   - If the second element is not `true`, the backend connection is down — cause 1. Resolve it via [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable).
2. Confirm the MongoDB server is reachable from the node's host:
   ```sh
   nc -vz <mongo-host> 27017
   ```
   - Expected: the connection succeeds.
   - If it succeeds but the `PUT` still returns `500`, the server is rejecting the write — cause 2; inspect the MongoDB server log.

### Resolution

*(Normative.)*

- For cause 1: the data store `shall` be restored to a reachable, healthy state per [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable); the `PUT` then returns `201`.
- For cause 2: the MongoDB credentials and `auth_source` `shall` match a user permitted to write the configured database, per the [data-store configuration reference §5.2](../configuration/data-store.md#52-backend_opts-for-mongodb).

> [!NOTE]
> The write is two steps — the authentication subscription, then the profile — and the first error short-circuits (confirmed in `store/3`). A `500` can therefore leave the authentication subscription stored but not the profile; re-issuing the same `PUT` after the store is healthy restores both, because the resource is create-or-replace.

### Prevention

*(Informative.)* Verifying the MongoDB connection (the [data-store configuration reference §7](../configuration/data-store.md#7-verify) check) before a provisioning campaign catches a down backend before the writes fail.

### Related

- [Provisioning interface reference §7](../interfaces/provisioning.md#7-status--result-codes) — the `500` code.
- [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable) — MongoDB unreachable.

---

## TS-PROV-004: The provisioning API cannot be reached (connection refused)

### Symptom

A request to the provisioning API fails at the transport layer — `curl` reports `Connection refused` (or a timeout) — and no HTTP status is returned at all. This differs from a `404`, which would confirm the listener is up.

### Affected component

`udr_provision` — the provisioning HTTP listener (`udr_provision_listener`) and its bind address.

### Likely causes

*(Ordered, most probable first.)*

1. The request is made from another host, but the listener `ip` is bound to loopback (`{127,0,0,1}`, the shipped default), so it is reachable only from the node's own host.
2. The request uses a port other than the configured `port` (shipped default `8090`).
3. The listener did not start — for example the configured `port` is already held by another process, so the listener failed to bind at boot.

### Diagnosis

1. Confirm the listener is bound, and on which address, from the node's host:
   ```sh
   ss -ltn '( sport = :8090 )'
   ```
   - Expected: a socket on the configured `ip`/`port`.
   - If it shows `127.0.0.1:8090` and the request came from another host, cause 1 applies.
   - If it shows nothing, no provisioning listener is bound — cause 3.
2. From the node's own host, confirm the listener answers (this isolates "not bound" from "not reachable from elsewhere"):
   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8090/provision/v1/subscribers/001010000000001
   ```
   - Expected: `404` (the listener is up; no such subscriber). A `404` here with a refused connection from another host confirms cause 1.
   - A refused connection even from the node's own host points at cause 3.
3. For cause 3, confirm whether another process holds the port:
   ```sh
   ss -ltnp '( sport = :8090 )'
   ```
   - If a different process is listed on `8090`, the provisioning listener could not bind it.

### Resolution

*(Normative.)*

- For cause 1: to provision from another host, `ip` `shall` be set to a routable address of the node, or to `{0,0,0,0}`, per the [provisioning configuration reference §5.1](../configuration/provisioning.md#51-ip). Because the API is unauthenticated, where `ip` is non-loopback, network-level access control `shall` restrict which hosts can reach the port.
- For cause 2: the consumer `shall` use the configured `port`.
- For cause 3: the configured `port` `shall` be free on the chosen `ip`; if another process holds it, the conflict `shall` be resolved or a different free `port` chosen, after which the node is restarted.

> [!CAUTION]
> Binding the provisioning `ip` to a routable or wildcard address exposes unauthenticated create/read/delete of every subscriber — including secret key material — to every host that can reach the port. Where `ip` is non-loopback, restrict the port to a trusted management network, per the [provisioning configuration reference §5.1](../configuration/provisioning.md#51-ip).

### Prevention

*(Informative.)* The [provisioning configuration reference §7](../configuration/provisioning.md#7-verify) confirms the bound socket and a `404` answer as part of bring-up; running it after a configuration change catches a loopback-only or unbound listener before a remote operator hits a refused connection.

### Related

- [Provisioning configuration reference §5.1, §7](../configuration/provisioning.md#51-ip) — `ip`, `port`, and the bind verification.
- [`RUN-LIFECYCLE-001`](../operations/lifecycle.md) — confirm the node and its applications started.
