---
id: S6A-PROC-RST
name: Reset
spec: 3GPP TS 29.272
spec_clause: "5.2.4.1"
category: Fault Recovery
initiator: HSS
peer: MME
maps_to:
  - request: Reset-Request (RSR)
    answer:  Reset-Answer (RSA)
    command_code: 322
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-RST — Reset

> [!NOTE]
> Abbreviations: HSS (Home Subscriber Server), MME (Mobility Management Entity),
> SGSN (Serving GPRS Support Node), UE (User Equipment), IMSI (International
> Mobile Subscriber Identity), MCC/MNC (Mobile Country/Network Code), MSIN
> (Mobile Subscriber Identification Number), AVP (Attribute-Value Pair). This is
> an HSS-initiated procedure on S6a (HSS↔MME) and S6d (HSS↔SGSN).

## Purpose

(Informative.) The Reset procedure lets the HSS tell the MME and SGSN that it has
restarted and may have lost the current serving-node identities of some
subscribers. Because the HSS can then no longer reliably send Cancel Location (see
[[S6A-PROC-CL]]) or Insert Subscriber Data (see [[S6A-PROC-ISD]]) for those
subscribers, the serving nodes mark the affected records so they trigger a
restoration procedure on next contact (typically Update Location, see
[[S6A-PROC-UL]]).

> [!NOTE]
> Release 16 also allows the Reset procedure to be used for operation-and-
> maintenance actions — for example to enable a planned HSS outage without service
> interruption, or to add, modify or delete subscription data shared by multiple
> subscribers. For shared-data updates the RSR carries Subscription-Data or
> Subscription-Data-Deletion (scoped by Reset-IDs); the serving node then applies
> the change as if an individual IDR or DSR had been received per subscriber,
> without marking those records as needing restoration.

## Trigger

The HSS invokes the procedure after a restart (failure recovery), to indicate to
all relevant MMEs, SGSNs and combined MME/SGSNs that it may have lost current
serving-node bindings. The HSS may also invoke it (without a restart) to update
subscription data shared by multiple subscribers, or as part of O&M actions.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | HSS | Sends RSR, optionally scoping the affected subscribers with a User-Id list. |
| Peer | MME (S6a) / SGSN (S6d) | Marks impacted subscriber records as "Location Information not confirmed in HSS" and answers with RSA. |

## Diameter mapping

Request → Answer: **Reset-Request (RSR) → Reset-Answer (RSA)**, command code
**322**, Application-Id **16777251** (S6a/S6d).

RSR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Id | (O) | One or more User-Ids (leading IMSI digits: MCC, MNC, leading MSIN digits) scoping the affected subscriber set; used when the Reset-ID feature is not supported and the failure is limited to those subscribers. |
| Reset-ID | (O) | One or more Reset-IDs identifying the impacted subscribers (e.g. by failed hardware component) when the Reset-ID feature is supported. |
| Subscription-Data | (O) | Subscription data to add to or replace in the impacted subscribers' profiles; present only with Reset-ID, and absent if Subscription-Data-Deletion is present. |
| Subscription-Data-Deletion | (O) | Identification of subscription data to delete from the impacted subscribers' profiles; present only with Reset-ID, and absent if Subscription-Data is present. |
| Supported-Features | (O) | Features supported by the origin host. |

> [!NOTE]
> Release 16 adds the Reset-ID, Subscription-Data and Subscription-Data-Deletion
> AVPs to the RSR. Reset-ID scopes a Reset to subscribers bound to a specific
> fallible HSS resource; Subscription-Data / Subscription-Data-Deletion turn the
> Reset into a bulk shared-subscription-data update or deletion.

RSA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome of the operation. |
| Supported-Features | (O) | Features supported by the serving node. |

## Procedure steps

> [!IMPORTANT]
> Reset is HSS-initiated. The steps below describe the HSS sender role, which is
> the role this catalog tracks.

The HSS-side behaviour:

1. The HSS shall use this procedure to indicate to all relevant MMEs, SGSNs and
   combined MME/SGSNs that it has restarted and may have lost the current MME-
   Identity and SGSN-Identity of some of its subscribers.
2. The HSS may also use this procedure to indicate that it has updated subscription
   data shared by some of its subscribers.
3. When the Reset-ID feature is not supported by the serving node, the HSS may
   include a list of User-Ids identifying a subset of subscribers, when the failure
   is limited to those subscribers.
4. When the Reset-ID feature is supported, the HSS may instead include one or more
   Reset-ID AVPs identifying the impacted subscribers (e.g. those associated with a
   failed hardware component).
5. For a shared-subscription-data update, the HSS shall include Reset-ID together
   with Subscription-Data (to add/replace data) or Subscription-Data-Deletion (to
   remove data); the two are mutually exclusive.
6. The HSS should invoke this procedure toward a combined MME/SGSN only once, even
   when some impacted subscribers are attached via UTRAN/GERAN and others via
   E-UTRAN.

> [!NOTE]
> Receiver behaviour (informative): the MME/SGSN marks impacted records "Location
> Information Confirmed in HSS" as "Not Confirmed" (using the Origin-Host and any
> User-Id list to scope them), then triggers the restoration procedure at the next
> authenticated radio contact.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | The serving node accepted the reset notification. |

> [!NOTE]
> Clause 5.2.4.1.1 states explicitly that there are no Experimental-Result codes
> applicable for this command.

## Related procedures

- [[S6A-PROC-UL]] — the restoration triggered by Reset re-runs Update Location.
- [[S6A-PROC-CL]] / [[S6A-PROC-ISD]] — the HSS-initiated operations Reset
  compensates for after a restart.

## Spec references

- TS 29.272, clause 5.2.4.1 (Reset): General 5.2.4.1.1, HSS behaviour 5.2.4.1.3.
- TS 29.272, clause 7.2.15 (RSR) and 7.2.16 (RSA); command code 322 (Table 7.2.2/1).
- TS 29.272, clause 7.3.50 (User-Id), 7.3.184 (Reset-ID), 7.3.208
  (Subscription-Data-Deletion).

## Support status

**Status:** implemented (pragmatic core) — Cycle ⑦ 2026-06-09.

(Informative.) After a recovery event the HSS fans a bare RSR out to every distinct
registered (non-purged) serving node and absorbs the RSA.

**Implemented**

- RSR/RSA (command 322) added to the Diameter dictionary.
- `udr_diameter_codec:rsr_request/1` — builds the outbound RSR (Destination-Host and
  Destination-Realm; no per-subscriber scoping AVPs in the bare Reset).
- `udr_data:registered_serving_nodes/0` — enumerates the distinct, non-purged serving
  nodes across all 3GPP access registrations via the backend-agnostic `udr_db:find/2`.
- `udr_hss:reset/0` — maps each distinct node to a `{reset, Info}` effect (system-wide,
  not under a per-IMSI lock).
- `udr_diameter_s6a:reset/0` — public trigger; fans an RSR out to each node via the
  shared `udr_diameter_s6a:originate/3` outbound helper; RSA is absorbed fire-and-forget.

**Deferred (backlog)**

- Automatic restart/failure-recovery trigger — no restart-detection yet; the procedure
  is exposed via `reset/0` for operator or supervisory invocation.
- User-Id and Reset-ID subscriber scoping (bare RSR only for now).
- Subscription-Data / Subscription-Data-Deletion carried in an RSR (the Rel-16
  shared-subscription-data update/delete path).
- RSA result processing beyond absorb (error logging, retry policy).
- Supported-Features negotiation.

**Tests:** `apps/udr_hss/test/udr_hss_reset_SUITE.erl` (fan-out, dedup,
exclude-purged); RSR/RSA codec cases (`rsr_roundtrip`, `rsa_roundtrip`, `rsr_request`)
in `apps/udr_diameter/test/udr_diameter_codec_SUITE.erl`; on-wire `rsr` case in
`apps/udr_diameter/test/udr_diameter_SUITE.erl`.
