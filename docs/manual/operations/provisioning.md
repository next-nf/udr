# Operations Runbook: Subscriber Provisioning

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers provisioning subscribers through the admin provisioning HTTP API served by `udr_api`: creating or replacing a single subscriber, reading one back, deleting one, and provisioning many in bulk. It is for operators populating the subscriber base. The full request and response contract — the body schema, validation, the read view, and every status code — is defined in the [provisioning interface reference](../interfaces/provisioning.md); this runbook directs the operator through the task and does not repeat the schema.

> [!CAUTION]
> The provisioning API is unauthenticated and the shipped listener binds to `127.0.0.1:8090`. Any caller that can reach the listener can create, read, or delete any subscriber, and credentials cross the wire in clear. The listener `shall` be bound only to a trusted management interface; see the [provisioning configuration reference](../configuration/provisioning.md). Secret-material handling is covered in [`RUN-SECRETS-001`](secrets.md).

> [!CAUTION]
> With the default in-memory [ETS](../glossary.md) backend, every provisioned subscriber is lost when the node stops. Bulk-provisioning many subscribers into an ETS-backed node and then restarting it loses them all. Where provisioned data is to persist, select the [MongoDB](../glossary.md) backend first (see [`RUN-BACKEND-001`](backend.md)).

---

## RUN-PROVISION-001: Provision, read, delete, and bulk-load subscribers

### Purpose

*(Informative.)* This procedure creates a subscriber's authentication credentials and optional profile so that the subscriber authenticates over [S6a](../glossary.md), reads a subscriber back to confirm storage, removes a subscriber, and loads many subscribers from a list. An operator runs it to onboard, audit, offboard, and batch-load subscribers.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node is running and the provisioning API is reachable on its configured `ip`/`port` (shipped default `127.0.0.1:8090`). See [`RUN-LIFECYCLE-001`](lifecycle.md).
- Each [IMSI](../glossary.md) to provision is known. Where a `PUT` for an existing IMSI is intended to overwrite it, that overwrite is intended (the store is create-or-replace).
- For each subscriber, the authentication inputs are known: [Ki](../glossary.md), [AMF](../glossary.md), and exactly one of [OPc](../glossary.md) or [OP](../glossary.md). The body schema and validation are defined in the [provisioning interface reference](../interfaces/provisioning.md) §5.1.
- `curl` is available for the HTTP steps; `bash` is available for the bulk step.

### Inputs and privileges

- Network reach to the provisioning listener.
- Per subscriber: IMSI, Ki (hex), AMF (hex), and one of OPc or OP (hex); optionally `algorithm`, `sqn`, and a `profile`.

> [!IMPORTANT]
> Operational Ki and OPc values `shall not` be drawn from public examples. The values shown below are well-known public test vectors used only to make the examples reproducible. See [`RUN-SECRETS-001`](secrets.md).

### Steps

1. **Provision a single subscriber.** Set the IMSI and send a `PUT` with the `auth` object (and optional `profile`):

   ```sh
   IMSI=001010000000001
   curl -sS -o /dev/null -w '%{http_code}\n' -X PUT \
     -H 'content-type: application/json' \
     "http://127.0.0.1:8090/provision/v1/subscribers/${IMSI}" \
     -d '{
       "auth": {
         "ki":  "465b5ce8b199b49faa5f0a2ee238a6bc",
         "opc": "cd63cb71954a9f4e48a5994e37a02baf",
         "amf": "8000",
         "sqn": 0
       },
       "profile": {}
     }'
   ```

2. **Read a subscriber back.** Send a `GET` for the same IMSI:

   ```sh
   curl -sS "http://127.0.0.1:8090/provision/v1/subscribers/${IMSI}"
   ```

   The read view returns authentication metadata and the profile, and withholds `ki` and `opc` (see the [interface reference](../interfaces/provisioning.md) §5.2).

3. **Delete a subscriber.** Send a `DELETE` for the IMSI:

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' -X DELETE \
     "http://127.0.0.1:8090/provision/v1/subscribers/${IMSI}"
   ```

4. **Bulk-provision from a list.** The provisioning API exposes no batch endpoint; it routes only the single per-IMSI resource (confirmed in `udr_api_app.erl`: one route, `/provision/v1/subscribers/:imsi`). Bulk provisioning is therefore a scripted loop of per-IMSI `PUT` requests. Prepare a newline-delimited file `subscribers.tsv` with one subscriber per line, fields `imsi`, `ki`, `opc`, `amf` separated by tabs, then run:

   ```sh
   while IFS=$'\t' read -r imsi ki opc amf; do
     [ -z "$imsi" ] && continue
     code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
       -H 'content-type: application/json' \
       "http://127.0.0.1:8090/provision/v1/subscribers/${imsi}" \
       -d "{\"auth\":{\"ki\":\"${ki}\",\"opc\":\"${opc}\",\"amf\":\"${amf}\"}}")
     printf '%s\t%s\n' "$imsi" "$code"
   done < subscribers.tsv
   ```

   Each line of output is the IMSI and the HTTP status its `PUT` returned. A subscriber that derives OPc from OP instead of supplying OPc uses an `op` field in place of `opc`; see the [interface reference](../interfaces/provisioning.md) §5.1.

> [!NOTE]
> The loop above sends requests sequentially and prints one status per IMSI so a failed line is visible. It is deliberately simple rather than concurrent; per-IMSI session locking serializes writes for one IMSI but the script does not depend on that.

### Verify

*(Observable outcome — see the [interface reference](../interfaces/provisioning.md) §8.)*

- Single provision (Step 1): the `PUT` `shall` return `201`.
- Read (Step 2): the `GET` `shall` return `200 OK` with an `auth` object containing `algorithm`, `amf`, and `sqn`, and containing no `ki` or `opc`.
- Delete (Step 3): the `DELETE` `shall` return `204`. A subsequent `GET` for the same IMSI `shall` return `404`.
- Bulk (Step 4): every line of the loop output `shall` show status `201`. Any other status identifies the IMSI that failed and its reason (see the [interface reference](../interfaces/provisioning.md) §7).
- End to end: an [AIR](../glossary.md) for a provisioned IMSI yields authentication vectors with `Result-Code` `2001` and, when a trace exporter is configured, an `s6a.AIR` [OpenTelemetry](../glossary.md) span (see [`RUN-S6A-PEER-001`](s6a-peer.md) and the [S6a interface reference](../interfaces/s6a.md) §8).

### Rollback / on failure

- A `PUT` that returns `400` was rejected by validation; the error body names the cause (missing `auth`, missing `ki`/`amf`, neither `opc` nor `op`, or an unknown `algorithm`). Correct the body and resend. The status codes are listed in the [interface reference](../interfaces/provisioning.md) §7.
- A `PUT` that returns `500` failed at the storage layer; confirm the backend is healthy (for MongoDB, see [`RUN-BACKEND-001`](backend.md) and the [data-store reference](../configuration/data-store.md) §7), then resend.
- To undo a provision, `DELETE` the IMSI (Step 3); the delete is idempotent and returns `204` even for an unknown IMSI.
- For a bulk load, the per-line status output identifies which IMSIs failed; re-run only those lines after correcting their input.

### Related

- [Provisioning interface reference](../interfaces/provisioning.md) — body schema, read view, and status codes.
- [Provisioning configuration reference](../configuration/provisioning.md) — bind address and the trusted-interface requirement.
- [`RUN-S6A-PEER-001`](s6a-peer.md) — verify a provisioned subscriber authenticates over S6a.
- [`RUN-BACKEND-001`](backend.md) — select MongoDB so provisioned data persists.
- [`RUN-SECRETS-001`](secrets.md) — handling Ki and OPc safely.
