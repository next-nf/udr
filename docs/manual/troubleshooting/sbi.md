# Troubleshooting: SBI — Nudr-DR (`udr_sbi`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers symptoms an operator observes on the 5G [SBI](../glossary.md) [Nudr](../glossary.md)-DR data-repository listener served by the `udr_sbi` application: a `400` for a `ueId` that is not in the expected form, a `404` for a subscriber that is not provisioned, a `500` on the registration resource, and the operational exposure of long-term key material returned in clear by the authentication-subscription resource. The status codes and error bodies referenced here are defined in the [SBI interface reference §7](../interfaces/sbi.md#7-status--result-codes); the listener configuration is defined in the [SBI configuration reference](../configuration/sbi.md).

> [!NOTE]
> All SBI error bodies are `application/problem+json` ([ProblemDetails](../interfaces/sbi.md#2-terms)): an object with `status`, `title`, and `detail`. The `detail` strings quoted below are the exact values the handlers return.

---

## TS-SBI-001: A request returns `400` with detail "invalid ueId (expected imsi-<digits>)"

### Symptom

A `GET`, `PUT`, or `DELETE` on any Nudr-DR resource returns `400 Bad Request` with an `application/problem+json` body whose `detail` is `invalid ueId (expected imsi-<digits>)`. The request never reaches the storage layer.

### Affected component

`udr_sbi` — the `ueId` parser (`udr_sbi:ue_imsi/1`), shared by all three resource handlers.

### Likely causes

*(Ordered, most probable first.)*

1. The `{ueId}` path segment is the bare IMSI digits, with no `imsi-` prefix (the most common integration mistake; the provisioning API uses the bare IMSI, the SBI does not).
2. The `{ueId}` uses a different NAI/`type-value` prefix (for example `msisdn-` or `nai-`) that this interface does not accept.
3. The `{ueId}` is `imsi-` with no digits after it (an empty IMSI).

### Diagnosis

1. Inspect the `{ueId}` path segment actually sent. Compare it against the required form `imsi-<digits>`.
   - Expected: `imsi-` followed by one or more digits, for example `imsi-001010000000001`.
   - If it is the bare digits `001010000000001`, cause 1 applies.
   - If it carries a different prefix, cause 2 applies.
   - If it is exactly `imsi-` with nothing after, cause 3 applies (an empty IMSI is rejected).
2. Confirm the contrast with a correctly formed request:
   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/provisioned-data/am-data
   ```
   - Expected: `404` for an unprovisioned subscriber, or `200` for a provisioned one — either confirms the `ueId` form was accepted and the `400` was specifically the `ueId` format.

### Resolution

*(Normative.)*

- For all causes: the consumer `shall` address the subscriber as `imsi-<digits>`, where `<digits>` is the non-empty [IMSI](../glossary.md), per the [SBI interface reference §3](../interfaces/sbi.md#3-transport-and-conventions). The IMSI used as the storage key is the part after `imsi-`.

> [!IMPORTANT]
> The SBI `ueId` (`imsi-<digits>`) and the provisioning API path (the bare IMSI, no prefix) differ deliberately. A subscriber provisioned at `/provision/v1/subscribers/001010000000001` is read over the SBI at `.../subscription-data/imsi-001010000000001/...`. Using the wrong form on either interface is the most common cause of this `400` and of a spurious `404`.

### Prevention

*(Informative.)* The [SBI interface reference §8](../interfaces/sbi.md#8-verify) includes a `ueId`-validation check that returns this exact `400`; running it once against a new consumer integration confirms the consumer builds the path correctly.

### Related

- [SBI interface reference §3, §7](../interfaces/sbi.md#3-transport-and-conventions) — the `ueId` form and the `400` code.
- [TS-SBI-002](#ts-sbi-002-a-get-returns-404-for-a-subscriber-believed-provisioned) — `404` for a known subscriber.

---

## TS-SBI-002: A GET returns `404` for a subscriber believed provisioned

### Symptom

A `GET` on an SBI resource returns `404 Not Found` for a subscriber the operator believes is provisioned. The `detail` names which resource was missing: `authentication subscription not found`, `am-data not found`, or `no serving-node registration`, depending on the resource requested.

### Affected component

`udr_sbi` — `udr_sbi_auth_h`, `udr_sbi_am_h`, or `udr_sbi_registration_h`, over the data store.

### Likely causes

*(Ordered, most probable first.)*

1. The subscriber is genuinely not provisioned for the requested resource. The three resources are independent: a subscriber can have an authentication subscription (so `IF-SBI-001` returns `200`) yet have no serving-node registration (so `IF-SBI-003` returns `404`) until a `ULR` or a `PUT` creates one.
2. The IMSI in the `ueId` does not match the IMSI under which the subscriber was provisioned (a formatting difference after the `imsi-` prefix).
3. The subscriber was provisioned on an [ETS](../glossary.md)-backed node that has since restarted, discarding the in-memory data.

### Diagnosis

1. Read the `detail` field of the `404` body to learn which resource is missing.
   - `authentication subscription not found` — there is no `auth` object for the IMSI.
   - `am-data not found` — there is no subscription profile for the IMSI.
   - `no serving-node registration` — there is no `amf-3gpp-access` context for the IMSI (no `ULR` and no SBI `PUT` has created one).
2. Confirm the subscriber exists at all over the provisioning API, using the **bare** IMSI (no `imsi-` prefix):
   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' \
     http://127.0.0.1:8090/provision/v1/subscribers/<imsi>
   ```
   - Expected if provisioned: `200`.
   - If `404`, the subscriber has no authentication subscription — cause 1 (genuinely not provisioned) or cause 3 (lost on restart).
3. If the provisioning `GET` returns `200` but the SBI `GET` returns `404` for the registration resource specifically, that is expected for a subscriber that has not yet attached: the `amf-3gpp-access` context is written only by a `ULR` or an SBI `PUT`, not by provisioning. This is cause 1, not a fault.
4. If the provisioning `GET` returns `200` but the SBI `GET` for an existing resource returns `404`, compare the IMSI after `imsi-` against the provisioned IMSI for a byte-for-byte match — cause 2.

### Resolution

*(Normative.)*

- For cause 1 (authentication or am-data missing): the subscriber `shall` be provisioned per [`RUN-PROVISION-001`](../operations/provisioning.md) before the resource is read.
- For cause 1 (registration missing): a serving-node registration `shall` first be created, either by an MME `ULR` or by an SBI `PUT` on `amf-3gpp-access` ([`IF-SBI-004`](../interfaces/sbi.md#54-if-sbi-004--put-amf-3gpp-access)). Until then a `404` is correct.
- For cause 2: the IMSI in the `ueId` after `imsi-` `shall` equal the provisioned IMSI.
- For cause 3: where data is to survive a restart, the MongoDB backend `shall` be selected per the [data-store configuration reference §5.1](../configuration/data-store.md#51-backend). See [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart).

### Prevention

*(Informative.)* A `404` on the registration resource for a never-attached subscriber is normal; the SBI [Verify step §8](../interfaces/sbi.md#8-verify) uses exactly that `404` to confirm the listener is reachable. Reserve concern for a `404` on `authentication-subscription` or `am-data` for an IMSI the operator did provision.

### Related

- [SBI interface reference §5, §7](../interfaces/sbi.md#5-operation-detail) — the three resources and the `404` code.
- [Provisioning API interface reference](../interfaces/provisioning.md) — provisioning by bare IMSI.
- [TS-DB-003](data-store.md#ts-db-003-provisioned-data-disappears-after-a-node-restart) — data lost after restart.

---

## TS-SBI-003: A PUT or DELETE on amf-3gpp-access returns `500` with detail "storage error"

### Symptom

A `PUT` or `DELETE` on `.../context-data/amf-3gpp-access` returns `500 Internal Server Error` with an `application/problem+json` body whose `detail` is `storage error`. The same request shape works against a healthy node, and `GET`s that do not write may still appear to work from cached state.

### Affected component

`udr_sbi` — `udr_sbi_registration_h` (the `PUT` and `DELETE` clauses) — over the data store.

### Likely causes

*(Ordered, most probable first.)*

1. The configured data backend failed the write or delete. For the MongoDB backend, the connection is down or the database is unreachable; the storage call returns `{error, _}`, which the handler maps to `500`.
2. The MongoDB server is reachable but rejecting the operation (for example an authentication failure or a permissions problem on the database).

### Diagnosis

1. Confirm the resolved backend and, for MongoDB, the connection. At the node's console:
   ```erlang
   {udr_db:backend(), catch is_pid(udr_db_mongo_conn:conn())}.
   ```
   - Expected for a healthy MongoDB deployment: `{udr_db_mongo, true}`.
   - If the second element is not `true` (it raises or returns otherwise), the backend connection is down — cause 1. Resolve it via [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable).
2. Confirm the MongoDB server is reachable from the node's host:
   ```sh
   nc -vz <mongo-host> 27017
   ```
   - Expected: the connection succeeds.
   - If it fails, the database is unreachable — cause 1.
   - If it succeeds but writes still `500`, the server is rejecting the operation — cause 2; inspect the MongoDB server log for an authentication or authorization error.

### Resolution

*(Normative.)*

- For cause 1: the data store `shall` be restored to a reachable, healthy state per [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable); a `PUT` then returns `204` and a `DELETE` returns `204`.
- For cause 2: the MongoDB credentials and the database/`auth_source` `shall` match a user permitted to write the configured database, per the [data-store configuration reference §5.2](../configuration/data-store.md#52-backend_opts-for-mongodb).

> [!NOTE]
> A `DELETE` that succeeds is idempotent and returns `204` even when nothing was registered (confirmed in `udr_sbi_registration_h.erl`). A `500` on `DELETE` therefore indicates a real storage error, not a missing registration.

### Prevention

*(Informative.)* Keeping the MongoDB backend's connection verified (the [data-store configuration reference §7](../configuration/data-store.md#7-verify) gives the `is_pid(udr_db_mongo_conn:conn())` check) catches a down connection before a consumer's write hits the `500`.

### Related

- [SBI interface reference §5.4, §5.5, §7](../interfaces/sbi.md#54-if-sbi-004--put-amf-3gpp-access) — the `500` on the registration resource.
- [TS-DB-001](data-store.md#ts-db-001-the-node-fails-to-start-or-data-operations-error-because-mongodb-is-unreachable) — MongoDB unreachable.

---

## TS-SBI-004: The authentication-subscription resource returns Ki and OPc in clear

### Symptom

A `GET` on `.../authentication-data/authentication-subscription` returns `200 OK` with a JSON body that includes `ki` and `opc` as lowercase hexadecimal strings — the subscriber's long-term secret key material — in clear. This is not a malfunction; it is the documented behavior of this resource. The concern is operational: where the SBI listener is exposed beyond a trusted network, this resource discloses every subscriber's permanent credentials.

### Affected component

`udr_sbi` — `udr_sbi_auth_h` / `udr_sbi:auth_view/1`, and the `udr_sbi` listener bind address.

### Likely causes

*(Ordered, most probable first.)*

1. The SBI listener `ip` is bound to a routable or wildcard address (for example `{0,0,0,0}`) reachable from an untrusted network, so any host that can reach the port can read the key material.
2. The listener is on loopback as shipped, but a reverse proxy or port-forward exposes it without adding authentication or restricting access.

### Diagnosis

1. Confirm the bind address of the SBI listener on the node's host:
   ```sh
   ss -ltn '( sport = :8080 )'
   ```
   - Expected for a hardened deployment: a socket on loopback (`127.0.0.1:8080`) or on a management-only address with network access control in front of it.
   - If it shows `0.0.0.0:8080` or a routable address reachable from an untrusted network, cause 1 applies.
2. Confirm what the resource actually returns, from a host on the same exposure as a potential attacker:
   ```sh
   curl -s http://<sbi-address>:8080/nudr-dr/v1/subscription-data/imsi-<imsi>/authentication-data/authentication-subscription
   ```
   - Observation: a `200` body containing `ki` and `opc` confirms the key material is reachable from that host. The handler performs no credential check, so reachability equals disclosure.

### Resolution

*(Normative.)*

- The SBI listener `shall not` be exposed to an untrusted network, because it returns long-term key material in clear and performs no authentication (confirmed in `udr_sbi:auth_view/1`; warned in the [SBI interface reference §5.1](../interfaces/sbi.md#51-if-sbi-001--get-authentication-subscription)).
- For cause 1: `ip` `shall` be bound only to an interface reachable from a trusted network, per the [SBI configuration reference §5.1](../configuration/sbi.md#51-ip); where it is bound to a non-loopback address, network-level access control `shall` restrict which hosts can reach the port.
- For cause 2: any proxy or forward that exposes the SBI `shall` enforce equivalent network-level restriction, since the application adds none of its own.

> [!CAUTION]
> This resource discloses [Ki](../glossary.md) and [OPc](../glossary.md) — the permanent secrets shared with the SIM — to any host that can reach the listener. Exposure of these enables impersonation of the subscriber. Treat reachability of the SBI port from an untrusted host as a credential compromise.

### Prevention

*(Informative.)* Handling of secret material, including the exposure surface of this resource, is covered by [`RUN-SECRETS-001`](../operations/secrets.md). Hardening of the SBI is the subject of the planned security documentation.

### Related

- [SBI interface reference §5.1](../interfaces/sbi.md#51-if-sbi-001--get-authentication-subscription) — the key-material warning.
- [SBI configuration reference §5.1](../configuration/sbi.md#51-ip) — binding the listener.
- [`RUN-SECRETS-001`](../operations/secrets.md) — handling Ki and OPc safely.
