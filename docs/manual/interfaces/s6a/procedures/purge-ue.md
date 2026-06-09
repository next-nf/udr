---
id: S6A-PROC-PU
name: Purge UE
spec: 3GPP TS 29.272
spec_clause: "5.2.1.3"
category: Location Management
initiator: MME
peer: HSS
maps_to:
  - request: Purge-UE-Request (PUR)
    answer:  Purge-UE-Answer (PUA)
    command_code: 321
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-PU — Purge UE

> [!NOTE]
> Abbreviations: MME (Mobility Management Entity), SGSN (Serving GPRS Support
> Node), HSS (Home Subscriber Server), UE (User Equipment), IMSI (International
> Mobile Subscriber Identity), AVP (Attribute-Value Pair), M-TMSI / P-TMSI
> (M-/Packet- Temporary Mobile Subscriber Identity). The MME drives this on S6a;
> the SGSN drives the equivalent on S6d.

## Purpose

(Informative.) The Purge UE procedure tells the HSS that the subscriber's profile
has been deleted from the MME or SGSN — for example through operator (MMI)
interaction or automatically after long UE inactivity. It allows the HSS to mark
the UE as purged so that no Insert Subscriber Data (see [[S6A-PROC-ISD]]) or
Cancel Location (see [[S6A-PROC-CL]]) is attempted toward a node that no longer
holds the record.

## Trigger

The MME or SGSN invokes the procedure when it deletes the subscriber's profile
from its database due to MMI interaction or after long UE inactivity.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | MME (S6a) / SGSN (S6d) | Sends PUR with the IMSI; on success may freeze the M-TMSI / P-TMSI as directed by the answer. |
| Peer | HSS | Sets the "UE purged" flag, decides which temporary identities to freeze, and answers with PUA. |

## Diameter mapping

Request → Answer: **Purge-UE-Request (PUR) → Purge-UE-Answer (PUA)**, command code
**321**, Application-Id **16777251** (S6a/S6d).

PUR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| PUR-Flags | (O) | Bit mask: UE Purged in MME (bit 0), UE Purged in SGSN (bit 1) — a combined MME/SGSN uses these to request a partial purge of one node only. |
| EPS-Location-Information | (C) | Last known EPS location information of the purged UE; present if available. |
| Supported-Features | (O) | Features supported by the origin host. |

> [!NOTE]
> Release 16 carries EPS-Location-Information in the PUR so the HSS can store the
> UE's last known location when it is purged (later usable for state/location
> requests via [[S6A-PROC-ISD]]).

PUA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome; the only applicable Experimental-Result is User Unknown. |
| PUA-Flags | (C) | Bit mask "freeze M-TMSI" / "freeze P-TMSI"; present only when Result-Code is DIAMETER_SUCCESS. |
| Supported-Features | (O) | Features supported by the HSS. |

## Procedure steps

On receiving a PUR, the HSS:

1. Check whether the IMSI is known. The HSS shall return
   `DIAMETER_ERROR_USER_UNKNOWN` if it is not.
2. If the IMSI is known, the HSS shall set the result code to `DIAMETER_SUCCESS`
   and compare the Origin-Host identity with the stored MME-Identity and stored
   SGSN-Identity.
3. If the received identity matches both the stored MME-Identity and SGSN-Identity,
   the HSS shall, when it does not support Partial Purge or no partial-purge
   indication was given, set both "freeze M-TMSI" and "freeze P-TMSI" in the PUA,
   set both the "UE purged in MME" and "UE purged in SGSN" flags, and store the
   received last known EPS location information of the purged UE.
4. If the HSS supports Partial Purge and the combined MME/SGSN indicated a purge in
   only one node, the HSS shall set the PUA flag and the "UE purged" flag for that
   node only, and store the received last known MME or SGSN location information
   accordingly.
5. If the received identity matches the stored MME-Identity but not the SGSN-
   Identity, the HSS shall set "freeze M-TMSI", clear "freeze P-TMSI", set "UE
   purged in MME", and store the received last known MME location information.
6. If the received identity matches the stored SGSN-Identity but not the MME-
   Identity, the HSS shall set "freeze P-TMSI", clear "freeze M-TMSI", set "UE
   purged in SGSN", and store the received last known SGSN location information.
7. If the received identity matches neither stored identity, the HSS shall clear
   both "freeze M-TMSI" and "freeze P-TMSI".

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | Purge recorded; PUA-Flags indicate which temporary identities to freeze. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | The IMSI is not known to the HSS. |

## Related procedures

- [[S6A-PROC-CL]] — once a UE is purged, the HSS suppresses Cancel Location to that
  node.
- [[S6A-PROC-UL]] — the HSS resets the "UE purged" flag on a subsequent Update
  Location.

## Spec references

- TS 29.272, clause 5.2.1.3 (Purge UE): General 5.2.1.3.1, HSS behaviour
  5.2.1.3.3.
- TS 29.272, clause 7.2.13 (PUR) and 7.2.14 (PUA); command code 321 (Table 7.2.2/1).
- TS 29.272, clause 7.3.48 (PUA-Flags), 7.3.149 (PUR-Flags).

## Support status

**Status:** implemented (pragmatic core) — Cycle ② 2026-06-09.

(Informative.) PUR is handled end to end; the purge is attributed to the requesting
node and the M-TMSI freeze + UE-purged marking follow the registered-MME comparison.

**Implemented**

- Purging-node identity decoded from the PUR Origin-Host AVP:
  `udr_diameter_codec:decode_pur/1`.
- Origin-Host vs stored `serving_mme_host` comparison and `ue_purged` marking — purge
  from the registered serving MME sets `<<"ue_purged">> => true` and answers
  Freeze-M-TMSI; purge from any other node answers success with no freeze and no purge
  mark: `udr_hss:do_pur/1`.
- PUA-Flags Freeze-M-TMSI driven by the comparison result (no longer hardcoded):
  `udr_diameter_codec:encode_pua_answer/1`.
- Step 1 user-unknown (5001) for an unprovisioned subscriber: `udr_hss:do_pur/1`.
- Cancel Location suppressed toward a previous node that has the UE marked purged;
  purged flag cleared on re-registration ([[S6A-PROC-UL]]):
  `udr_hss:clr_effect_if_moved/3`.

**Deferred (backlog)**

- EPS-Location-Information storage (needs a grouped-AVP dictionary addition; no
  consumer yet).
- PUR-Flags partial-purge handling and the separate SGSN identity / Freeze-P-TMSI /
  UE-purged-in-SGSN semantics (this HSS models the MME side).
- Supported-Features.

**Tests:** `apps/udr_hss/test/udr_hss_ulr_SUITE.erl` (`pur_from_registered_mme_marks_purged_and_freezes`,
`pur_from_other_mme_no_freeze`, `pur_unknown_subscriber_returns_user_unknown`,
`ulr_after_purge_suppresses_clr`),
`apps/udr_diameter/test/udr_diameter_codec_SUITE.erl` (`pur_decode`, `encode_pua_answer`,
`encode_pua_answer_freeze`), and the lifecycle cases in
`apps/udr_hss/test/udr_hss_integration_SUITE.erl` and
`apps/udr_hss/test/udr_hss_dist_SUITE.erl`.
