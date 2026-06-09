---
id: S6A-PROC-UL
name: Update Location
spec: 3GPP TS 29.272
spec_clause: "5.2.1.1"
category: Location Management
initiator: MME
peer: HSS
maps_to:
  - request: Update-Location-Request (ULR)
    answer:  Update-Location-Answer (ULA)
    command_code: 316
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-UL — Update Location

> [!NOTE]
> Abbreviations used on first occurrence: MME (Mobility Management Entity),
> SGSN (Serving GPRS Support Node), HSS (Home Subscriber Server),
> IMSI (International Mobile Subscriber Identity), EPS (Evolved Packet System),
> RAT (Radio Access Technology), APN (Access Point Name), AVP (Attribute-Value
> Pair), PLMN (Public Land Mobile Network), ODB (Operator Determined Barring),
> UE (User Equipment), VPLMN (Visited PLMN). The S6a reference point connects an
> MME to the HSS; the parallel S6d reference point connects an SGSN to the HSS.
> This catalog documents the HSS role; the procedure is identical on S6a and S6d
> except where noted.

## Purpose

(Informative.) The Update Location procedure registers the serving node currently
handling a subscriber and synchronises the subscriber's profile into that serving
node. It is invoked by the MME (over S6a) or the SGSN (over S6d):

- to inform the HSS of the identity of the MME or SGSN currently serving the user;
- to update the MME or SGSN with user subscription data;
- to provide the HSS with other user data, such as Terminal Information or UE
  SRVCC (Single Radio Voice Call Continuity) capability.

## Trigger

The MME or SGSN invokes the procedure when it needs to update the serving-node
identity stored in the HSS — for example at initial attach, at an inter-MME
tracking-area update or inter-SGSN routing-area update, or on radio contact with
the UE after an HSS reset (see [[S6A-PROC-RST]]).

> [!NOTE]
> For a UE receiving emergency services that was not successfully authenticated,
> the MME or SGSN does not invoke this procedure.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | MME (S6a) / SGSN (S6d) | Sends ULR with its identity, RAT type, and the visited PLMN; stores the returned subscription profile. |
| Peer | HSS | Validates the subscriber, registers the new serving node, cancels the previous registration, and returns the subscription data in the ULA. |

## Diameter mapping

Request → Answer: **Update-Location-Request (ULR) → Update-Location-Answer (ULA)**,
command code **316**, Application-Id **16777251** (S6a/S6d).

ULR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| ULR-Flags | (M) | Bit mask (see below): Single-Registration-Indication (bit 0), S6a/S6d-Indicator (bit 1), Skip-Subscriber-Data (bit 2), GPRS-Subscription-Data-Indicator (bit 3), Node-Type-Indicator (bit 4), Initial-Attach-Indicator (bit 5), PS-LCS-Not-Supported-By-UE (bit 6), SMS-Only-Indication (bit 7), Dual-Registration-5G-Indicator (bit 8). |
| Visited-PLMN-Id | (M) | MCC/MNC of the visited PLMN; used for roaming-based features. |
| RAT-Type | (M) | The radio access type the UE is using. |
| Supported-Features | (O) | Features supported by the origin host. |
| Terminal-Information | (O) | Mobile equipment data; only IMEI and Software-Version are used on S6a/S6d. |
| Active-APN | (O) | Active APNs and assigned PDN GW identities, e.g. to restore PDN GW data after a reset. |
| UE-SRVCC-Capability | (C) | UE SRVCC support indication, when available. |
| SGSN-Number / MME-Number-for-MT-SMS | (C) | ISDN number of the serving node for SMS routing. |
| SMS-Register-Request | (C) | Request by an MME ("SMS in MME") or SGSN ("SMS in SGSN") to be registered for SMS. |
| Coupled-Node-Diameter-ID | (C) | Diameter identity of the coupled MME/SGSN, so the HSS can detect a single combined MME/SGSN. |

> [!NOTE]
> Release 16 adds the SMS-Only-Indication (bit 7) and Dual-Registration-5G-Indicator
> (bit 8) flags to ULR-Flags. The Dual-Registration-5G-Indicator, when set by an MME,
> tells the combined HSS+UDM not to send a 5GC deregistration notification to a
> registered AMF (see TS 29.503 / TS 29.563).

ULA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome of the operation. |
| ULA-Flags | (C) | Bit mask: Separation Indication (bit 0), MME Registered for SMS (bit 1); present only when Result-Code is DIAMETER_SUCCESS. |
| Subscription-Data | (C) | Complete subscription profile; present on success unless "Skip Subscriber Data" was set in the request. |
| Error-Diagnostic | (O) | Refines "Unknown EPS Subscription" and "Roaming Not Allowed" outcomes. |
| Supported-Features | (O) | Features supported by the HSS. |

> [!NOTE]
> Release 16 adds the "MME Registered for SMS" flag (bit 1) to ULA-Flags; the HSS
> sets it to confirm it has registered the MME for the "SMS in MME" service.

## Procedure steps

On receiving a ULR, the HSS:

1. Check whether subscription data exists for the IMSI. The HSS shall return
   `DIAMETER_ERROR_USER_UNKNOWN` if there is no subscription of any type (EPS,
   GPRS or CS) for the IMSI.
2. Over S6a, the HSS shall return `DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION` if the
   subscriber has no APN configuration. Over S6d, it shall return the same error
   if the subscriber has neither an APN configuration profile nor GPRS
   subscription data.
3. Over S6a, the HSS shall return `DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION` when
   the request comes from an MME that does not support the "Non-IP PDN Type APNs"
   feature and the subscription profile contains only APN configurations of type
   "Non-IP".
4. The HSS may add Error-Diagnostic with `DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION`
   to indicate whether GPRS subscription data is subscribed.
5. Check whether the RAT type is allowed. The HSS shall return
   `DIAMETER_ERROR_RAT_NOT_ALLOWED` if it is not.
6. Check whether access to EPC is allowed, based on the active Core Network
   Restrictions of the subscriber. The HSS shall return
   `DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION` if access to EPC is restricted.
7. Check whether roaming is barred in the VPLMN due to ODB. The HSS shall return
   `DIAMETER_ERROR_ROAMING_NOT_ALLOWED` if so. The HSS may add Error-Diagnostic
   to indicate the type of ODB, except where the ODB indicates "Barring of
   Roaming", in which case Error-Diagnostic shall not be included.
8. Over S6d, if the HSS supports the "SGSN CAMEL Capability" feature, the SGSN
   indicates support of it, and the subscriber has SGSN CAMEL Subscription data,
   the HSS shall return `DIAMETER_ERROR_CAMEL_SUBSCRIPTION_PRESENT`.
9. Over S6a, the HSS shall send a Cancel Location (see [[S6A-PROC-CL]]) with
   Cancellation-Type `MME_UPDATE_PROCEDURE` to the previous MME (if any), replace
   the stored MME-Identity with the value in the Origin-Host AVP, reset the
   "UE purged in MME" flag, and delete any stored last-known MME location
   information.
10. Over S6a, if the "Single-Registration-Indication" flag was set, the HSS shall
    additionally send a Cancel Location with Cancellation-Type
    `SGSN_UPDATE_PROCEDURE` to the SGSN and delete the stored SGSN address and
    number; if instead the "Initial-Attach-Indicator" flag was set (and
    Single-Registration was not), the HSS shall send a Cancel Location with
    Cancellation-Type `INITIAL_ATTACH_PROCEDURE` to the SGSN if there is an SGSN
    registration.
11. Over S6d, the HSS shall send a Cancel Location with Cancellation-Type
    `SGSN_UPDATE_PROCEDURE` to the previous SGSN (if any), replace the stored
    SGSN-Identity, reset the "UE purged in SGSN" flag, and delete any stored
    last-known SGSN location information. If the "Initial-Attach-Indicator" flag
    was set, the HSS shall send a Cancel Location with Cancellation-Type
    `INITIAL_ATTACH_PROCEDURE` to the MME if there is an MME registration.
12. If a URRP-MME (S6a) or URRP-SGSN (S6d) parameter is set for the user, the HSS
    shall clear it and send an indication to the corresponding Service Related
    Entities.
13. The HSS shall store new Terminal Information and/or UE SRVCC capability if
    present; if UE SRVCC capability is absent, it shall record that it has no
    knowledge of the capability.
14. If the request includes the list of active APNs, the HSS shall delete stored
    dynamic PDN GW information and replace it with the received values.
15. If the HSS supports the "SMS in MME"/"SMS in SGSN" feature and the serving
    node requested SMS registration (via SMS-Register-Request and/or the
    SMS-Only-Indication flag), the HSS shall, if it accepts SMS via that node,
    register the node for SMS, store the supplied serving-node number as the MSC
    number for MT SMS, and (over S6a) set the "MME Registered for SMS" flag in
    ULA-Flags.
16. If no error result code has been determined, the HSS shall include the
    subscription data in the ULA (subject to the ULR-Flags and supported features,
    and unless "Skip Subscriber Data" was set) and return `DIAMETER_SUCCESS`.
17. On success, the HSS shall set the Separation Indication in the response.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | Serving node registered; subscription data returned. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | No subscription of any type exists for the IMSI. |
| DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION | 5420 | The subscriber has no EPS (and, on S6d, no GPRS) subscription. |
| DIAMETER_ERROR_RAT_NOT_ALLOWED | 5421 | The RAT type the UE is using is not allowed for the IMSI. |
| DIAMETER_ERROR_ROAMING_NOT_ALLOWED | 5004 | The subscriber is not allowed to roam in the MME/SGSN area (ODB). |
| DIAMETER_ERROR_CAMEL_SUBSCRIPTION_PRESENT | 4182 | Over S6d only: the subscriber to be registered has SGSN CAMEL Subscription data (transient failure). |

## Related procedures

- [[S6A-PROC-CL]] — the HSS sends Cancel Location to the previous serving node as
  part of this procedure.
- [[S6A-PROC-AIR]] — authentication vectors are normally fetched before location
  update at attach.
- [[S6A-PROC-RST]] — after an HSS reset, the serving node re-runs Update Location.
- [[S6A-PROC-NOT]] — used for serving-node-internal updates that do not change the
  serving node.

## Spec references

- TS 29.272, clause 5.2.1.1 (Update Location): General 5.2.1.1.1, HSS behaviour
  5.2.1.1.3.
- TS 29.272, clause 7.2.3 (ULR) and 7.2.4 (ULA); command code 316 (Table 7.2.2/1).
- TS 29.272, clause 7.4 (Result-Code and Experimental-Result values).

## Support status

**Status:** implemented (pragmatic core) — Cycle ① 2026-06-09.

(Informative.) The happy path works end to end. ULR-Flags are decoded; correct
Cancellation-Type is derived per trigger; Skip-Subscriber-Data is honoured. The
remaining gaps are explicitly deferred as out-of-scope for pragmatic core.

> [!NOTE]
> The prior Cancellation-Type bug (hardcoded `Subscription Withdrawal (2)` on the
> Update-Location-driven CLR) was fixed in Cycle ①.

**Implemented**

- ULR decode/dispatch and ULA encode: `apps/udr_diameter/src/udr_diameter_s6a.erl:64`;
  codec decode `apps/udr_diameter/src/udr_diameter_codec.erl:42`, encode `:64`; HSS
  logic `apps/udr_hss/src/udr_hss.erl:42` (`handle_ulr/1`) → `do_ulr/1` (`:45`), under
  the per-IMSI cluster lock.
- Step 1 user-unknown (5001): `udr_hss.erl:46`.
- Step 9: registers the serving MME from the Origin-Host and emits a Cancel Location
  to the previous MME on change: `udr_hss.erl:51`, `:61` (`clr_effect_if_moved/3`).
- Correct Cancellation-Type per trigger: `MME Update Procedure (0)` for an inter-MME
  move; `Initial Attach Procedure (4)` when the Initial-Attach-Indicator flag is set.
  Derived in `clr_effect_if_moved/3`; mapped to the wire value in
  `udr_diameter_codec:clr_request/1` (private `cancellation_type/1`).
- ULR-Flags decode (`decode_ulr/1`): `skip_subscriber_data` (bit 2) and
  `initial_attach` (bit 5) booleans extracted and passed into `do_ulr/1`.
- Skip-Subscriber-Data honoured: `do_ulr/1` returns an answer without the profile
  when the flag is set; `encode_ulr_answer/1` omits the `Subscription-Data` AVP.
- Step 16 return Subscription-Data + 2001: `udr_hss.erl:58`; codec `:64`.
- Step 17 Separation Indication: hardcoded `ULA-Flags => [1]`
  (`udr_diameter_codec.erl:67`).
- Cancel Location is suppressed toward a previous node that marked the UE purged, and
  the purged flag is cleared on re-registration ([[S6A-PROC-PU]]) —
  `udr_hss:clr_effect_if_moved/3`.

**Deferred (backlog)**

- RAT-Type check (5421), roaming / ODB check (5004), EPC-restriction check, and
  EPS/APN-subscription validation (5420 unreachable) — requires an access-restriction
  data model; no CAMEL handling (4182).
- Single-Registration-Indication, SMS-Only-Indication, and Dual-Registration-5G-
  Indicator flag handling; SGSN / S6d cancel branches.
- Terminal-Information / UE-SRVCC / Active-APN / dynamic-PDN-GW storage (steps 13–14).
- URRP clearing (step 12); last-known-location deletion.
- Full Subscription-Data (currently minimal: Subscriber-Status + optional AMBR + one
  APN config); Supported-Features; Error-Diagnostic; SMS-in-MME registration and the
  ULA "MME Registered for SMS" flag.

**Tests:** `apps/udr_hss/test/udr_hss_ulr_SUITE.erl` (`ulr_new_mme_emits_cancel_location`,
`ulr_initial_attach_uses_initial_attach_cancellation`, `ulr_skip_subscriber_data_omits_profile`),
`apps/udr_diameter/test/udr_diameter_codec_SUITE.erl` (`clr_request`, `clr_roundtrip`,
`ulr_decode`, `ulr_decode_flags`, `encode_ulr_answer_skip`),
`apps/udr_diameter/test/udr_diameter_SUITE.erl` (`ulr_then_clr` — asserts
Cancellation-Type 0 on the wire via `udr_diameter_test_mme:recorded_clr/1`),
`apps/udr_hss/test/udr_hss_dist_SUITE.erl`.
