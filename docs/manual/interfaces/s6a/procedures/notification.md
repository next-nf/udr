---
id: S6A-PROC-NOT
name: Notification
spec: 3GPP TS 29.272
spec_clause: "5.2.5.1"
category: Notification
initiator: MME
peer: HSS
maps_to:
  - request: Notify-Request (NOR)
    answer:  Notify-Answer (NOA)
    command_code: 323
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-NOT — Notification

> [!NOTE]
> Abbreviations: MME (Mobility Management Entity), SGSN (Serving GPRS Support
> Node), HSS (Home Subscriber Server), UE (User Equipment), IMSI (International
> Mobile Subscriber Identity), AVP (Attribute-Value Pair), APN (Access Point
> Name), PDN GW (Packet Data Network Gateway), SRVCC (Single Radio Voice Call
> Continuity), URRP (UE Reachability Request Parameter), MNRF/MNRG (Mobile-station
> Not Reachable Flag/for-GPRS). The MME drives this on S6a; the SGSN drives the
> equivalent on S6d.

## Purpose

(Informative.) The Notification procedure lets the MME or SGSN inform the HSS of
events that occur without an inter-node location change. It is used to notify the
HSS about:

- an update of Terminal Information or of UE SRVCC capability;
- assignment/change of a dynamically allocated PDN GW for an APN;
- the need to send a Cancel Location to the current SGSN (MME only);
- the UE becoming reachable, or having memory available, to receive short messages;
- the UE becoming reachable (when the HSS requested reachability notification);
- an update of the Homogeneous Support of IMS Voice over PS Sessions;
- removal of the MME's registration for SMS (MME only).

## Trigger

The MME or SGSN invokes the procedure when one of the above events occurs while
the serving node remains unchanged — for example a Terminal Information change,
selection of a new dynamic PDN GW, the UE becoming reachable (clearing URRP set by
[[S6A-PROC-ISD]]), or a change in homogeneous IMS-voice support.

> [!NOTE]
> If the MME or SGSN supports emergency services, it does not invoke the
> Notification procedure for emergency-attached UEs.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | MME (S6a) / SGSN (S6d) | Sends NOR carrying the changed information and the relevant NOR-Flags. |
| Peer | HSS | Validates that the originator is the registered serving node, stores the new data / performs the consequent actions, and answers with NOA. |

## Diameter mapping

Request → Answer: **Notify-Request (NOR) → Notify-Answer (NOA)**, command code
**323**, Application-Id **16777251** (S6a/S6d).

NOR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| NOR-Flags | (C) | Bit mask: Single-Registration-Indication (bit 0), SGSN area restricted (bit 1), Ready for SM from SGSN (bit 2), UE Reachable from MME (bit 3), Reserved/deprecated (bit 4), UE Reachable from SGSN (bit 5), Ready for SM from MME (bit 6), Homogeneous Support of IMS Voice Over PS Sessions (bit 7), S6a/S6d-Indicator (bit 8), Removal of MME Registration for SMS (bit 9). Absence means all bits 0. |
| Terminal-Information | (C) | New mobile equipment data on change (IMEI / Software-Version only). |
| MIP6-Agent-Info | (C) | Identity of a newly selected dynamic PDN GW. |
| Visited-Network-Identifier | (C) | PLMN of the PDN GW when its identity does not contain an FQDN. |
| Context-Identifier / Service-Selection | (O/C) | APN configuration / APN that the selected PDN GW correlates to. |
| Alert-Reason | (C) | Indicates the subscriber is present or the MS has memory available. |
| UE-SRVCC-Capability | (C) | New UE SRVCC capability on change. |
| Homogeneous-Support-of-IMS-Voice-Over-PS-Sessions | (C) | Present when this support changes to SUPPORTED or NOT_SUPPORTED (used with the bit-7 NOR-Flag). |
| Maximum-UE-Availability-Time | (C) | Latest time the UE will be reachable, for short-message buffering. |
| Monitoring-Event-Config-Status | (C) | Status of Monitoring event configurations (e.g. failed at the MME/SGSN or deleted at the SCEF), so the HSS can cancel or suspend them. |
| EPS-Location-Information | (C) | Last known EPS location, when reported. |
| Supported-Features | (O) | Features supported by the origin host. |

> [!NOTE]
> Release 16 adds the Monitoring-Event-Config-Status reporting path: an MME/SGSN
> uses NOR to report monitoring-event configuration failures (or SCEF-side
> deletion), and the HSS reacts with a Monitoring-event cancellation or suspension
> procedure toward the SCEF (see TS 29.336).

NOA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome; applicable Experimental-Result is User Unknown (and, per HSS behaviour, Unknown Serving Node). |
| Supported-Features | (O) | Features supported by the HSS. |

## Procedure steps

On receiving a NOR, the HSS:

1. Check whether the IMSI is known. The HSS shall return
   `DIAMETER_ERROR_USER_UNKNOWN` if it is not.
2. If the IMSI is known but the originating MME or SGSN is not currently registered
   in the HSS for that UE, the HSS shall return
   `DIAMETER_ERROR_UNKNOWN_SERVING_NODE`.
3. If the IMSI is known and the originator is the registered serving node, the HSS
   shall set the result code to `DIAMETER_SUCCESS` (unless otherwise stated below)
   and:
   - store the new Terminal Information if present;
   - store the new UE SRVCC capability if present;
   - store the new PDN GW and PLMN ID for an APN if present and the APN is in the
     subscription and the PDN GW is dynamically allocated; otherwise the HSS shall
     not store it and shall set the result code to `DIAMETER_ERROR_UNABLE_TO_COMPLY`;
   - store the new PDN GW, PLMN ID and the APN itself if the APN is absent but a
     wildcard APN is present in the subscription;
   - if the Emergency Services IE is present with the Emergency-Indication flag set,
     store the new PDN GW as the one used for emergency PDN connections, not bound
     to any specific APN;
   - mark the location area as "restricted" if so indicated;
   - send Cancel Location (see [[S6A-PROC-CL]]) to the current SGSN if so indicated;
   - if the UE has become reachable, clear URRP-MME (on S6a) or URRP-SGSN (on S6d)
     and indicate UE reachability to the Service Related Entities;
   - on Alert-Reason, reset the MNRF (S6a) or MNRG (S6d) flag and send a MAP-Alert-
     Service-Centre message;
   - store the updated Homogeneous Support of IMS Voice over PS Sessions when so
     notified (per the bit-7 NOR-Flag and the accompanying AVP);
   - remove the MME registration for SMS, and the stored "MME number for SMS", when
     so notified (bit-9 NOR-Flag, S6a only);
   - when a Monitoring-Event-Config-Status AVP is present, trigger a Monitoring-event
     cancellation procedure (for events not authorised by the IWK-SCEF) or a
     suspension procedure (for events not configured at the MME/SGSN); when it
     indicates SCEF-side deletion of a configuration, locally delete that Monitoring
     Event Configuration without triggering a cancellation.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | The HSS stored the notified data / performed the action. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | The IMSI is not known to the HSS. |
| DIAMETER_ERROR_UNKNOWN_SERVING_NODE | 5423 | The notifying MME/SGSN is not the node currently registered in the HSS for this UE. |
| DIAMETER_ERROR_UNABLE_TO_COMPLY | 5012 | The HSS could not store the notified PDN GW data (APN not present and no wildcard APN). |

## Related procedures

- [[S6A-PROC-ISD]] — sets URRP; Notification reports the resulting UE reachability.
- [[S6A-PROC-CL]] — the HSS may send Cancel Location to the SGSN as a result of a
  Notification.
- [[S6A-PROC-UL]] — used instead of Notification when the serving node changes.

## Spec references

- TS 29.272, clause 5.2.5.1 (Notification): General 5.2.5.1.1, HSS behaviour
  5.2.5.1.3.
- TS 29.272, clause 7.2.17 (NOR) and 7.2.18 (NOA); command code 323 (Table 7.2.2/1).
- TS 29.272, clause 7.3.49 (NOR-Flags); 7.4.3.6 (5423).

> [!NOTE]
> `DIAMETER_ERROR_UNABLE_TO_COMPLY` is referenced in the NOR HSS behaviour text
> (5.2.5.1.3); its numeric value (5012) is defined in the base/common Diameter
> specifications rather than in TS 29.272 clause 7.4. The value 5012 is confirmed
> against the Result-Code mapping tables in TS 29.272 V16.8.0, which cite it by
> number.

## Support status

**Status:** implemented (pragmatic core) — Cycle ③ 2026-06-09.

(Informative.) Inbound NOR is handled end to end; the notification is validated against
the registered serving node and the notified Terminal-Information is stored.

**Implemented**

- NOR/NOA (323) command and NOR-Flags AVP (1443) added to the dictionary:
  `apps/udr_diameter/dia/diameter_3gpp_s6a.dia`.
- NOR decode (IMSI, notifying-node identity from Origin-Host, optional Terminal-Information):
  `udr_diameter_codec:decode_nor/1`.
- Serving-node validation: unknown IMSI → `DIAMETER_ERROR_USER_UNKNOWN` (5001); notifying
  node not the registered serving MME → `DIAMETER_ERROR_UNKNOWN_SERVING_NODE` (5423):
  `udr_hss:do_nor/1`.
- Terminal-Information stored on the registration on success: `udr_hss:do_nor/1`.
- NOA encode including the 5423 experimental-result mapping:
  `udr_diameter_codec:encode_noa_answer/1`.
- NOR dispatch (guard, span name, dispatch clause): `udr_diameter_s6a`.

**Deferred (backlog)**

- NOR-Flags semantics: URRP clearing; UE-reachability and Ready-for-SM indications;
  removal of MME SMS registration (bit 9).
- UE-SRVCC-Capability storage.
- Dynamic PDN GW (MIP6-Agent-Info) storage.
- Alert-Reason / MNRF reset + MAP-Alert-Service-Centre.
- Homogeneous-Support-of-IMS-Voice-Over-PS storage.
- Monitoring-Event-Config-Status handling.
- EPS-Location-Information storage.
- Supported-Features.

**Tests:** `apps/udr_hss/test/udr_hss_nor_SUITE.erl` (3 cases:
`nor_success_stores_terminal_info`, `nor_unknown_imsi`, `nor_unknown_serving_node`),
`apps/udr_diameter/test/udr_diameter_codec_SUITE.erl` (`nor_roundtrip`, `noa_roundtrip`,
`nor_decode`, `nor_decode_no_ti`, `encode_noa_answer`, `encode_noa_unknown_serving_node`),
and the on-wire `nor` case in `apps/udr_diameter/test/udr_diameter_SUITE.erl`.
