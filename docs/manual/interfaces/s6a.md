# Interface Reference: S6a Diameter (`udr_diameter`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the [S6a](../glossary.md) [Diameter](../glossary.md) interface implemented by the `udr_diameter` application. It documents the four S6a procedures the system handles end to end: Authentication-Information ([AIR](../glossary.md)/[AIA](../glossary.md)), Update-Location ([ULR](../glossary.md)/[ULA](../glossary.md)), Purge-UE ([PUR](../glossary.md)/[PUA](../glossary.md)), and the HSS-initiated Cancel-Location ([CLR](../glossary.md)/[CLA](../glossary.md)). For each, it lists the request [AVPs](../glossary.md) the code consumes, the answer AVPs it produces, and the Diameter Result-Code or Experimental-Result values it returns.

The Diameter transport (TCP, port 3868) and the Diameter identity this node presents (Origin-Host, Origin-Realm) are configuration, not part of this contract; they are covered in the [S6a Diameter configuration reference](../configuration/diameter.md). Authentication-vector cryptography (MILENAGE) and the on-disk subscriber schema are out of scope.

> [!NOTE]
> The S6a Diameter dictionary modules (`diameter_3gpp_s6a.erl` / `.hrl`) are generated at build time from the OTP `diameter` dictionary and are not committed to the repository. The contract in this reference is therefore derived from the two source modules that the system owns: `udr_diameter_codec.erl` (which decodes request AVPs and encodes answer AVPs) and `udr_diameter_s6a.erl` (which dispatches commands and builds the common answer envelope). AVP names below are the dictionary-record field names those modules use.

## 2. Terms

Terms used below — S6a, Diameter, AVP, MME, HSS, AIR, AIA, ULR, ULA, PUR, PUA, CLR, CLA, IMSI, SQN, authentication vector — are defined in the [glossary](../glossary.md). Two further names are local to this interface:

- **Result-Code** — the Diameter base-protocol result AVP, used here for success (`2001`) and for the base error `5012`.
- **Experimental-Result** — the grouped AVP carrying a vendor-specific result, used here for the 3GPP (Vendor-Id `10415`) error codes `5001` and `5420`.

## 3. Transport and conventions

- **Protocol / transport:** Diameter (IETF RFC 6733) over TCP.
- **Endpoint:** the listener binds the endpoints in the `udr_diameter` `listen` key; the shipped default is `{tcp, {127,0,0,1}, 3868}`. See the [configuration reference](../configuration/diameter.md).
- **Application:** S6a, Auth-Application-Id `16777251`, Vendor-Id `10415` (3GPP). Registered under the alias `s6a` with dictionary `diameter_3gpp_s6a` (confirmed in `udr_diameter_srv.erl`, `init/1`).
- **Identity:** the node presents `origin_host` / `origin_realm` from configuration in every message it originates, and copies them into every answer it sends (confirmed in `udr_diameter_s6a.erl`, `reply/5`).
- **Authentication:** Diameter peer authentication is by the CER/CEA capability exchange and transport reachability only; there is no per-subscriber authorization of the peer. The listener `should` be bound to a trusted interface, as the [configuration reference](../configuration/diameter.md) requires.
- **Identifiers:** a subscriber is addressed by the `User-Name` AVP, which carries the [IMSI](../glossary.md).
- **Answer envelope:** every AIA, ULA, and PUA carries `Session-Id` (echoed from the request), `Auth-Session-State` = `1` (NO_STATE_MAINTAINED), `Origin-Host`, and `Origin-Realm`, in addition to the per-command AVPs in §5 (confirmed in `reply/5`).

## 4. Operations

| ID | Operation | Command (request / answer) | Initiator |
| --- | --- | --- | --- |
| `IF-S6A-001` | Obtain EPS authentication vectors | `AIR` / `AIA` | MME |
| `IF-S6A-002` | Register the serving MME and obtain subscription data | `ULR` / `ULA` | MME |
| `IF-S6A-003` | Mark the UE as purged from the MME | `PUR` / `PUA` | MME |
| `IF-S6A-004` | Cancel a stale registration at a previous MME | `CLR` / `CLA` | HSS (this node) |

> [!NOTE]
> Only `AIR`, `ULR`, and `PUR` are accepted as inbound requests (confirmed in `udr_diameter_s6a.erl`, `handle_request/3`). Any other inbound command is discarded. `CLR` is the one command this node *originates*; it is emitted as a side effect of a `ULR` (see `IF-S6A-004`).

## 5. Operation detail

### 5.1 `IF-S6A-001` — AIR / AIA

- **Purpose** *(informative):* the MME requests one or more EPS authentication vectors for a subscriber, typically at attach. The HSS advances the stored [SQN](../glossary.md), generates the vectors with MILENAGE, and returns them.
- **Request AVPs consumed** (confirmed in `udr_diameter_codec.erl`, `decode_air/1`):
  - `User-Name` — the IMSI. Required.
  - `Visited-PLMN-Id` — the 3-byte serving-network identity, used as a MILENAGE input. Required.
  - `Requested-EUTRAN-Authentication-Info` — grouped; from it the codec reads:
    - `Number-Of-Requested-Vectors` — the number of vectors to return. Defaults to `1` when absent.
    - `Re-Synchronization-Info` — when present, parsed as `RAND` (16 bytes) concatenated with `AUTS` (14 bytes) to drive an SQN resynchronization.
- **Answer AVPs produced** on success (confirmed in `encode_air_answer/1`):
  - `Result-Code` = `2001`.
  - `Authentication-Info`, containing a list of `E-UTRAN-Vector`, one per generated vector. Each vector carries `Item-Number`, `RAND`, `XRES`, `AUTN`, and `KASME` (confirmed in `eutran_vector/2`).
- **Resynchronization** *(informative):* when `Re-Synchronization-Info` is present and verifies, the stored SQN is repaired to `SQN_MS + 1` before vectors are generated. A resync whose MAC fails is ignored, and fresh vectors are still returned so the UE can resync again (confirmed in `udr_hss.erl`, `maybe_resync/5`).
- **Errors:** see §7. A subscriber with no authentication subscription returns `5001`; a CAS-exhausted SQN advance or a failed SQN repair returns `5012`.

### 5.2 `IF-S6A-002` — ULR / ULA

- **Purpose** *(informative):* the MME registers itself as the serving MME for the subscriber and obtains the subscription profile.
- **Request AVPs consumed** (confirmed in `decode_ulr/1`):
  - `User-Name` — the IMSI. Required.
  - `Origin-Host`, `Origin-Realm` — the MME's identity, stored as the serving-MME registration. Required.
  - `RAT-Type` — the radio access type; stored with the registration. Optional (`undefined` when absent).
  - `Visited-PLMN-Id` — stored with the registration. Optional (empty when absent).
- **Answer AVPs produced** on success (confirmed in `encode_ulr_answer/1`):
  - `Result-Code` = `2001`.
  - `ULA-Flags` = `1`.
  - `Subscription-Data`, a grouped AVP built from the stored profile (confirmed in `subscription_data/1`):
    - `Subscriber-Status` = `0` (SERVICE_GRANTED), always present.
    - `AMBR` (`Max-Requested-Bandwidth-UL` / `-DL`) — included only when the stored profile has an `ambr` object with `ul` and `dl`.
    - `APN-Configuration-Profile` — included only when the stored profile has an `apn_config_profile` with a `context_id`; the emitted APN config uses `PDN-Type` = `0` and `Service-Selection` = `"default"`.
- **Registration effect** *(informative):* on success the serving-MME registration is written. If a *different* MME was previously registered, the HSS emits a Cancel-Location effect against the old MME — see `IF-S6A-004` (confirmed in `udr_hss.erl`, `do_ulr/1` and `clr_effect_if_moved/2`).
- **Errors:** see §7. An unprovisioned subscriber returns `5001`.

### 5.3 `IF-S6A-003` — PUR / PUA

- **Purpose** *(informative):* the MME tells the HSS that it has purged the UE; the HSS clears the serving-MME registration.
- **Request AVPs consumed** (confirmed in `decode_pur/1`):
  - `User-Name` — the IMSI. Required. No other AVP is read.
- **Answer AVPs produced** on success (confirmed in `encode_pua_answer/1`):
  - `Result-Code` = `2001`.
  - `PUA-Flags` = `1`.
- **Effect** *(informative):* the serving-MME registration for the IMSI is deleted (confirmed in `udr_hss.erl`, `do_pur/1`).
- **Errors:** see §7. An unprovisioned subscriber returns `5001` (per TS 29.272 §7.3.3, noted in the source).

### 5.4 `IF-S6A-004` — CLR / CLA (HSS-initiated)

- **Purpose** *(informative):* when a subscriber re-registers through a new MME, the HSS tells the previously registered MME to cancel the subscriber's location. This system originates the `CLR`; it does not accept an inbound `CLR`.
- **Trigger:** a successful `ULR` (`IF-S6A-002`) whose serving MME differs from the one already registered. There is no other trigger.
- **Request AVPs produced** (confirmed in `udr_diameter_codec.erl`, `clr_request/1`, plus the envelope in `udr_diameter_s6a.erl`, `run_effect/1`):
  - `User-Name` — the IMSI.
  - `Destination-Host`, `Destination-Realm` — the previously registered MME's host and realm.
  - `Cancellation-Type` = `2` (SUBSCRIPTION_WITHDRAWAL).
  - Envelope: `Session-Id` (newly generated), `Auth-Session-State` = `1`, `Origin-Host`, `Origin-Realm`.
- **Delivery** *(informative):* the `CLR` is sent with `diameter:call(..., [detach])` — fire-and-forget. The matching `CLA` answer is absorbed and not acted upon (confirmed in `udr_diameter_s6a.erl`, `handle_answer/4`, commented "CLA absorbed").

> [!NOTE]
> Because the `CLR` is fire-and-forget, no Result-Code from the old MME's `CLA` is surfaced to the operator. Delivery of the `CLR` depends on a routable Diameter connection to the old MME's host and realm; if none exists, the `CLR` is not delivered and no error is raised on the `ULR` path.

## 6. Sequence

*The following sequence diagram is normative: the message order for an LTE attach (AIR then ULR) is the order the MME and HSS exchange S6a messages.*

```mermaid
sequenceDiagram
    participant MME
    participant HSS as HSS (udr_diameter)
    MME->>HSS: AIR (S6a) — request authentication vectors
    Note over HSS: read auth subscription, advance SQN,<br/>generate EPS-AKA vectors (MILENAGE)
    HSS-->>MME: AIA (S6a) — Authentication-Info (E-UTRAN-Vector list)
    MME->>HSS: ULR (S6a) — register serving MME
    Note over HSS: store registration; if MME changed,<br/>originate CLR to the old MME
    HSS-->>MME: ULA (S6a) — Subscription-Data
    opt serving MME changed
        HSS->>MME: CLR (S6a) — to the previous MME (fire-and-forget)
    end
```

## 7. Status / result codes

The codes below are every result the S6a path returns. Success uses the Diameter base `Result-Code` AVP; 3GPP-specific errors use the grouped `Experimental-Result` AVP with Vendor-Id `10415`; the generic failure uses the base `Result-Code` AVP. All are confirmed in `udr_diameter_codec.erl` (`encode_*` / `error_avps/1`) and `udr_diameter_s6a.erl` (`handle_request/3`).

| Code | AVP | Returned when | Confirmed in |
| --- | --- | --- | --- |
| `2001` (DIAMETER_SUCCESS) | `Result-Code` | AIR, ULR, or PUR completed successfully. | `encode_air_answer/1`, `encode_ulr_answer/1`, `encode_pua_answer/1` |
| `5001` (DIAMETER_ERROR_USER_UNKNOWN) | `Experimental-Result` (vendor 10415) | The subscriber has no authentication subscription (AIR) or no subscription profile (ULR, PUR). | `error_avps(user_unknown)`; `udr_hss.erl` `do_air/1`, `do_ulr/1`, `do_pur/1` |
| `5012` (DIAMETER_UNABLE_TO_COMPLY) | `Result-Code` | An AIR could not be served despite a known subscriber: the SQN advance exhausted its CAS retries, or an AUTS-resync SQN repair failed. | `error_avps(_Other)`; `udr_hss.erl` `do_air/1`, `maybe_resync/5` |
| `5005` (DIAMETER_MISSING_AVP) | answer message | The inbound request was malformed or missing a required AVP (the decode step reported errors). Returned before any application logic runs. | `udr_diameter_s6a.erl` `handle_request/3` (first clause) |

> [!NOTE]
> The codec also defines `5420` (DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION) for an `unknown_eps_subscription` result (`error_avps/1`). In the 0.1.0 code path no handler in `udr_hss.erl` returns that result, so `5420` is not emitted on any current request. It is listed here for completeness; confirm against source before relying on it.

> [!NOTE]
> An inbound command other than `AIR`, `ULR`, or `PUR` is silently discarded with no answer (the `discard` return in `handle_request/3`); the peer sees no reply for it.

## 8. Verify

- Confirm the listener is reachable: a peer's `CER` `shall` be answered with a `CEA` carrying the configured `Origin-Host`. See the [configuration reference](../configuration/diameter.md) §7.
- Confirm an `AIR` against a provisioned [IMSI](../glossary.md) returns an `AIA` with `Result-Code` = `2001` and an `Authentication-Info` AVP containing at least one `E-UTRAN-Vector`. The procedure produces an `s6a.AIR` [OpenTelemetry](../glossary.md) span with attribute `s6a.result` = `success` when a trace exporter is configured (confirmed in `udr_diameter_s6a.erl`, `handle_request/3`; see the [observability reference](../configuration/observability.md)).
- Confirm an `AIR` against an IMSI that is not provisioned returns an `AIA` whose `Experimental-Result` carries Vendor-Id `10415` and Experimental-Result-Code `5001`, and the span attribute `s6a.result` = `user_unknown`.
