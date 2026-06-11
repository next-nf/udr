# Quickstart: From Clone to First Authenticated Subscriber

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This document is a linear, copy-pasteable path that uses only what works out of the box: the default in-memory [ETS](glossary.md) backend and the [`rebar3 shell`](glossary.md) development node. It takes the operator from a built node to a provisioned subscriber whose authentication material is observed end to end.

Terms are defined in the [glossary](glossary.md). Prerequisites and the build are covered in [install.md](install.md); the architecture is in [overview.md](overview.md).

## 1. Pre-conditions

The following `shall` hold before starting:

- The prerequisites in [install.md](install.md) §1 are installed: [Erlang/OTP](glossary.md) 29 or later and [rebar3](glossary.md).
- The source has been obtained and `rebar3 compile` has succeeded ([install.md](install.md) §3).
- The shipped `config/sys.config` is in effect, so the data backend is the default [ETS](glossary.md) backend and the listeners bind to `127.0.0.1` on ports `3868` (S6a), `8080` (SBI), and `8090` (provisioning).
- `curl` is available for the HTTP steps.

> [!NOTE]
> No external database is needed. The default [ETS](glossary.md) backend holds all data in memory and is discarded when the node stops, which is the intended behavior for a quickstart.

## 2. Start the node

1. From the project root, start the development node:

   ```sh
   rebar3 shell
   ```

   **Verify.** The Erlang shell prompt appears, and the five umbrella applications are running. At the prompt:

   ```erlang
   [ A || {A,_,_} <- application:which_applications(),
          lists:member(A, [udr, udr_hss, udr_diameter, udr_sbi, udr_api]) ].
   ```

   The expected result lists all five applications (order may vary):

   ```erlang
   [udr_api,udr_sbi,udr_diameter,udr_hss,udr]
   ```

> [!NOTE]
> Leave this shell running. Steps 3, 4, and 5 use `curl` from a **second** terminal; step 6 uses the Erlang shell from this first terminal.

## 3. Provision one subscriber

The provisioning API is served by `udr_api` on `127.0.0.1:8090`. A subscriber is created or replaced with a `PUT` to `/provision/v1/subscribers/{imsi}`.

### Request contract

The request body is a JSON object. The handler accepts the following fields (confirmed in `apps/udr_api/src/udr_api_subscriber_h.erl` and `udr_api_subscriber.erl`):

| Field | Location | Required | Type | Meaning |
| --- | --- | --- | --- | --- |
| `auth` | top level | yes | object | The authentication credentials. A request without an `auth` object returns `400`. |
| `auth.ki` | inside `auth` | yes | hex string | The subscriber's permanent key [Ki](glossary.md), 16 bytes (32 hex digits). |
| `auth.amf` | inside `auth` | yes | hex string | The [AMF](glossary.md) Authentication Management Field, 2 bytes (4 hex digits). |
| `auth.opc` | inside `auth` | one of `opc` / `op` | hex string | The [OPc](glossary.md), 16 bytes (32 hex digits). |
| `auth.op` | inside `auth` | one of `opc` / `op` | hex string | The [OP](glossary.md), 16 bytes; OPc is derived from OP and Ki at provisioning if `opc` is absent. |
| `auth.algorithm` | inside `auth` | no | string | Defaults to `milenage`. An unknown value returns `400`. |
| `auth.sqn` | inside `auth` | no | integer | The initial [SQN](glossary.md). Defaults to `0`. |
| `profile` | top level | no | object | The EPS subscription profile, stored as supplied. Defaults to an empty object. |

> [!IMPORTANT]
> Each `auth` object `shall` carry `ki` and `amf`, and `shall` carry exactly one of `opc` or `op`. A request that supplies neither `opc` nor `op` returns `400` with the body `{"error":"auth requires 'opc' or 'op' (and 'ki','amf')"}`.

> [!NOTE]
> The [Ki](glossary.md) and [OPc](glossary.md) values below are well-known public test values. They are used here only to make the example reproducible; operational credentials `shall not` be drawn from public examples.

1. From a second terminal, provision IMSI `001010000000001`:

   ```sh
   curl -i -X PUT \
     -H 'Content-Type: application/json' \
     http://127.0.0.1:8090/provision/v1/subscribers/001010000000001 \
     -d '{
       "auth": {
         "ki":  "465b5ce8b199b49faa5f0a2ee238a6bc",
         "opc": "cd63cb71954a9f4e48a5994e37a02baf",
         "amf": "8000",
         "sqn": 0
       },
       "profile": {
         "subscriber-status": 0,
         "msisdn": "11112345678"
       }
     }'
   ```

   **Verify.** The response status is `201 Created` and the body is:

   ```json
   {"imsi":"001010000000001","status":"provisioned"}
   ```

## 4. Read the subscriber back

The provisioning API exposes a read at the same path with `GET`. The read view returns authentication metadata only — the [Ki](glossary.md) and [OPc](glossary.md) secrets are not included (confirmed in `udr_api_subscriber.erl`, `to_view/2`).

1. Read IMSI `001010000000001`:

   ```sh
   curl -i http://127.0.0.1:8090/provision/v1/subscribers/001010000000001
   ```

   **Verify.** The response status is `200 OK`, and the body contains the `auth` metadata and the `profile` supplied in step 3. The `auth` object reports the algorithm, the hex-encoded `amf`, and the `sqn`, and contains no `ki` or `opc`:

   ```json
   {
     "auth": {"algorithm": "milenage", "amf": "8000", "sqn": 0},
     "profile": {"subscriber-status": 0, "msisdn": "11112345678"}
   }
   ```

## 5. Read the subscriber over the SBI

The 5G [SBI](glossary.md) (Nudr-DR) is served by `udr_sbi` on `127.0.0.1:8080`. Its [ueId](glossary.md) path segment has the form `imsi-<digits>`; a ueId that does not match returns `400` (confirmed in `apps/udr_sbi/src/udr_sbi.erl`, `ue_imsi/1`).

### 5.1 Authentication subscription

1. Read the authentication subscription:

   ```sh
   curl -i http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/authentication-data/authentication-subscription
   ```

   **Verify.** The response status is `200 OK`. The body is the stored authentication subscription with `ki`, `opc`, and `amf` hex-encoded in lowercase (confirmed in `udr_sbi.erl`, `auth_view/1`):

   ```json
   {
     "algorithm": "milenage",
     "amf": "8000",
     "ki": "465b5ce8b199b49faa5f0a2ee238a6bc",
     "opc": "cd63cb71954a9f4e48a5994e37a02baf",
     "sqn": 0
   }
   ```

> [!WARNING]
> This SBI resource returns the long-term key material ([Ki](glossary.md) and [OPc](glossary.md)) in clear hex. On a real deployment the SBI listener `shall not` be exposed to untrusted networks. Hardening of the SBI is covered in [security.md](security.md).

### 5.2 Access-and-mobility data

The `am-data` resource returns the subscription profile minus the APN configuration (confirmed in `apps/udr_data/src/udr_data.erl`, `get_am_subscription/1`). The profile supplied in step 3 carries no APN configuration, so the whole profile is returned.

1. Read the access-and-mobility data:

   ```sh
   curl -i http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/provisioned-data/am-data
   ```

   **Verify.** The response status is `200 OK` and the body is the access-and-mobility view of the profile:

   ```json
   {"subscriber-status": 0, "msisdn": "11112345678"}
   ```

> [!NOTE]
> What steps 4 and 5 prove: the subscriber provisioned in step 3 is stored and readable through both the provisioning API and the SBI. They do not yet exercise [EPS-AKA](glossary.md) authentication; that is step 6.

## 6. Demonstrate authentication material end to end

> [!IMPORTANT]
> Exercising the full [S6a](glossary.md) [AIR](glossary.md) over Diameter requires a Diameter peer (an [MME](glossary.md) or a test client) to send the AIR. Connecting an MME is the subject of the [connect-an-MME runbook](operations/s6a-peer.md) (`RUN-S6A-PEER-001`). This step does **not** fake a `curl` against the Diameter listener; instead it produces the authentication material directly in the running node's Erlang shell, which is the same code path the AIR uses.

This step is run in the **first** terminal, at the Erlang shell from step 2.

### 6.1 Compute one EPS authentication vector (pure)

The function `udr_crypto:eps_vector/7` computes one [EPS authentication vector](glossary.md) (AV) for a supplied [RAND](glossary.md). It is pure and needs no stored subscriber (confirmed in `apps/udr_crypto/src/udr_crypto.erl`).

1. At the Erlang shell, compute a vector for the same credentials provisioned in step 3:

   ```erlang
   Algo = milenage,
   K    = binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
   OPc  = binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
   AMF  = binary:decode_hex(<<"8000">>),
   SQN  = <<0:48>>,
   RAND = binary:decode_hex(<<"23553cbe9637a89d218ae64dae47bf35">>),
   SnId = <<16#00, 16#f1, 16#10>>,
   AV   = udr_crypto:eps_vector(Algo, K, OPc, AMF, SQN, RAND, SnId).
   ```

   **Verify.** The call returns an `eps_av` native record carrying the four vector components (confirmed in `udr_crypto.erl`). Confirm each component has the expected length: [RAND](glossary.md) 16 bytes, [XRES](glossary.md) 8 bytes, [AUTN](glossary.md) 16 bytes, KASME 32 bytes:

   ```erlang
   [ byte_size(B) || B <- [AV#eps_av.rand, AV#eps_av.xres, AV#eps_av.autn, AV#eps_av.kasme] ].
   ```

   The expected result is:

   ```erlang
   [16,8,16,32]
   ```

> [!NOTE]
> The `#eps_av{}` record syntax is available at the shell because `udr_crypto` exports the record (`-export_record([eps_av])`). If the shell reports an unknown record, evaluate `rr(udr_crypto).` first to load the record definitions.

### 6.2 Run the HSS AIR path against the provisioned subscriber

The function `udr_hss:handle_air/1` is the same handler the S6a transport calls for an [AIR](glossary.md). It reads the provisioned authentication subscription through `udr_data`, advances the stored [SQN](glossary.md), and returns the generated vectors (confirmed in `apps/udr_hss/src/udr_hss.erl`). It requires the subscriber provisioned in step 3 and runs inside the per-IMSI cluster lock, both of which are satisfied in the running node.

1. At the Erlang shell, request two vectors for the provisioned IMSI:

   ```erlang
   {ok, Answer, Effects} =
       udr_hss:handle_air(#{imsi => <<"001010000000001">>,
                            visited_plmn => <<16#00,16#f1,16#10>>,
                            num_vectors => 2}).
   ```

   **Verify.** The call returns `{ok, Answer, Effects}` where `Answer` carries two vectors and `Effects` is the empty list. Confirm the vector count:

   ```erlang
   length(maps:get(vectors, Answer)).
   ```

   The expected result is:

   ```erlang
   2
   ```

2. Confirm that the AIR advanced the stored [SQN](glossary.md). Re-read the subscriber over the SBI from the second terminal:

   ```sh
   curl -s http://127.0.0.1:8080/nudr-dr/v1/subscription-data/imsi-001010000000001/authentication-data/authentication-subscription
   ```

   **Verify.** The `sqn` field is now `2` rather than `0`, because the AIR allocated two vectors and advanced the stored SQN by two (confirmed in `udr_data.erl`, `advance_sqn/2`):

   ```json
   "sqn": 2
   ```

> [!NOTE]
> What step 6 proves: the credentials provisioned in step 3 produce valid [EPS-AKA](glossary.md) authentication vectors through the same code the S6a [AIR](glossary.md) uses, and the AIR advances the per-subscriber [SQN](glossary.md). It does not prove S6a interoperability on the wire; that needs a Diameter peer and is the subject of the [connect-an-MME runbook](operations/s6a-peer.md).

## 7. Observing spans (optional)

> [!NOTE]
> The default `traces_exporter` in `config/sys.config` is `none`, so spans are **not** exported unless an exporter is configured. The S6a path produces spans named `s6a.AIR`, `s6a.ULR`, and `s6a.PUR` (confirmed in `apps/udr_diameter/src/udr_diameter_s6a.erl`). To export them, set `traces_exporter` and the OTLP endpoint as shown in the project `README.md`, then point the node at a collector. Tracing setup is covered in the [observability runbook](operations/observability.md) (`RUN-OBSERVABILITY-001`).

## 8. Next steps

- To select the [MongoDB](glossary.md) backend, set listener addresses for external peers, or change the S6a identity, see the [configuration references](configuration/README.md).
- To connect a real [MME](glossary.md) over [S6a](glossary.md) and observe AIR/ULR on the wire, see the [connect-an-MME runbook](operations/s6a-peer.md).
- To export traces and metrics to a collector, see the [observability runbook](operations/observability.md).
