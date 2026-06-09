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
support_status: partial          # assessed 2026-06-09 against code at main (c605b66)
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

**Status:** partial — assessed 2026-06-09 against the code at `main` (c605b66).

(Informative.) PUR/PUA is wired end to end with a correct known/unknown distinction,
but the Release-16 PUR-Flags / EPS-Location / identity-comparison semantics are absent
and PUA-Flags is a constant.

**Implemented**

- PUR decode/dispatch and PUA encode: `apps/udr_diameter/src/udr_diameter_s6a.erl:65`,
  `:90`; codec decode `apps/udr_diameter/src/udr_diameter_codec.erl:51`, encode `:74`;
  HSS logic `apps/udr_hss/src/udr_hss.erl:73` (`handle_pur`/`do_pur`).
- Step 1 user-unknown (5001): `udr_hss.erl:77`.
- Step 2 success for a known IMSI; the registration is deleted via
  `udr_data:delete_3gpp_access_registration/1` (`apps/udr_data/src/udr_data.erl:152`).

**Not yet implemented**

- PUR-Flags not decoded; no Partial Purge (steps 4–6).
- EPS-Location-Information never received or stored (step 3 onward).
- No Origin-Host vs stored MME-/SGSN-Identity comparison; PUA-Flags is hardcoded to
  `[1]` (`udr_diameter_codec.erl:77`), so the per-identity freeze logic (steps 3, 5,
  6, 7) is absent.
- No persistent "UE purged in MME/SGSN" flag — the code deletes the registration
  instead.
- Supported-Features not handled.

**Tests:** `apps/udr_hss/test/udr_hss_ulr_SUITE.erl:78`, `:86`;
`apps/udr_hss/test/udr_hss_integration_SUITE.erl:53`;
`apps/udr_hss/test/udr_hss_dist_SUITE.erl:140`. No wire-level PUR→PUA test asserts the
PUA-Flags / Result-Code.
