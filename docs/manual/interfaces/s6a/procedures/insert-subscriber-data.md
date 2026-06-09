---
id: S6A-PROC-ISD
name: Insert Subscriber Data
spec: 3GPP TS 29.272
spec_clause: "5.2.2.1"
category: Subscriber Data Handling
initiator: HSS
peer: MME
maps_to:
  - request: Insert-Subscriber-Data-Request (IDR)
    answer:  Insert-Subscriber-Data-Answer (IDA)
    command_code: 319
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-ISD — Insert Subscriber Data

> [!NOTE]
> Abbreviations: HSS (Home Subscriber Server), MME (Mobility Management Entity),
> SGSN (Serving GPRS Support Node), UE (User Equipment), IMSI (International
> Mobile Subscriber Identity), APN (Access Point Name), AVP (Attribute-Value
> Pair), ODB (Operator Determined Barring), T-ADS (Terminating Access Domain
> Selection), URRP (UE Reachability Request Parameter), PDN GW (Packet Data
> Network Gateway). This is an HSS-initiated procedure on S6a (HSS↔MME) and S6d
> (HSS↔SGSN).

## Purpose

(Informative.) The Insert Subscriber Data procedure updates and/or requests
specific user data in the MME or SGSN. The HSS invokes it to:

- push administrative changes to the user's subscription data;
- apply, change or remove ODB for the user;
- activate subscriber tracing in the serving node;
- request notification when the UE becomes reachable (UE Reachability Request);
- request T-ADS data, EPS user state, EPS location information, or the local time
  zone of the visited network;
- update a dynamically allocated PDN GW identity for an APN;
- indicate to the MME that it has been deregistered for SMS;
- request the MME/SGSN to run the HSS-based P-CSCF restoration procedure;
- configure, report or delete Monitoring events in the MME/SGSN;
- update the Active Time for power saving mode, or the Core Network Restrictions
  (5GC allowed / not allowed).

## Trigger

The HSS invokes the procedure when subscription data changes administratively
while the UE is registered at a serving node, or when a service-related entity (or
an application server) requests UE state, location, T-ADS, reachability or local
time-zone information that the serving node holds.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | HSS | Sends IDR carrying the changed Subscription-Data and/or request flags. |
| Peer | MME (S6a) / SGSN (S6d) | Adds/replaces the indicated data, returns requested state/location/T-ADS information, and answers with IDA. |

## Diameter mapping

Request → Answer: **Insert-Subscriber-Data-Request (IDR) →
Insert-Subscriber-Data-Answer (IDA)**, command code **319**, Application-Id
**16777251** (S6a/S6d).

IDR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| Subscription-Data | (M) | The part of the subscription profile to add or replace; included empty when the IDR is sent only to request state/location/T-ADS/local-time-zone/reachability data or to perform a flag-only action. |
| IDR-Flags | (C) | Bit mask (see below): UE-Reachability-Request (bit 0), T-ADS-Data-Request (bit 1), EPS-User-State-Request (bit 2), EPS-Location-Information-Request (bit 3), Current-Location-Request (bit 4), Local-Time-Zone-Request (bit 5), Remove-SMS-Registration (bit 6), RAT-Type-Requested (bit 7), P-CSCF-Restoration-Request (bit 8). |
| Reset-IDs | (O) | One or more Reset-IDs identifying the fallible HSS resources on which the subscriber depends, so a later Reset can scope the impacted subscribers. |
| Supported-Features | (O) | Features supported by the origin host. |

> [!NOTE]
> Release 16 adds the RAT-Type-Requested flag (bit 7) and the
> P-CSCF-Restoration-Request flag (bit 8) to IDR-Flags, and carries the Reset-IDs
> AVP in the IDR. RAT-Type-Requested is used only together with the
> EPS-Location-Information-Request bit.

IDA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome; the only applicable Experimental-Result is User Unknown. |
| IMS-Voice-Over-PS-Sessions-Supported | (C) | T-ADS result, when requested. |
| Last-UE-Activity-Time | (C) | Time of last radio contact, when requested. |
| RAT-Type | (C) | RAT at last radio contact, when requested. |
| EPS-User-State | (C) | Present if EPS user state was requested. |
| EPS-Location-Information | (C) | Present if EPS location information was requested. |
| Local-Time-Zone | (C) | Present if the local time zone was requested. |
| IDA-Flags | (C) | Bit mask of answer indications (e.g. SGSN Area Restricted). |
| Supported-Features | (O) | Features supported by the serving node. |

## Procedure steps

> [!IMPORTANT]
> Insert Subscriber Data is HSS-initiated. The steps below describe the HSS sender
> role, which is the role this catalog tracks. Receiver validation (e.g. returning
> User Unknown) is performed by the MME/SGSN.

The HSS-side behaviour:

1. The HSS shall use this procedure to replace a specific part of the user data
   stored in the MME or SGSN, or to add a specific part of user data.
2. The HSS shall include the Subscriber-Status AVP in the Subscription-Data when
   the value stored in the serving node needs to change; to remove all ODB
   categories it shall set Subscriber-Status to `SERVICE_GRANTED`.
3. The HSS shall include the Access-Restriction-Data AVP when the stored value
   needs to be modified.
4. The HSS shall include the APN-Configuration-Profile AVP when the default-APN
   Context-Identifier changes or at least one APN-Configuration is added or
   modified; the default APN configuration shall not contain the Wildcard APN.
5. When a service-related entity indicates the UE is unreachable, the HSS shall set
   the URRP-MME and/or URRP-SGSN parameter and send an IDR with the "UE
   Reachability Request" flag set, unless it knows the serving node does not
   support reachability notifications.
6. When state, location, T-ADS or local-time-zone data is requested and the
   serving node supports it, the HSS shall set the corresponding IDR-Flags bit; if
   the IDR is sent only to request such data, the Subscription-Data shall be
   included empty.
7. When the HSS determines that the MME shall be unregistered for SMS, it shall set
   the "Remove SMS Registration" bit in the IDR-Flags; if the IDR is sent only for
   that purpose, the Subscription-Data shall be included empty.
8. When the HSS needs the MME/SGSN to run the HSS-based P-CSCF restoration
   procedure and the node supports it, the HSS shall set the "P-CSCF Restoration
   Request" bit in the IDR-Flags; if the IDR is sent only for that purpose, the
   Subscription-Data shall be included empty.
9. When the HSS receives an SCEF request to configure or delete Monitoring events
   for the UE, it shall include the corresponding Monitoring-Event-Configuration
   AVP(s) in the Subscription-Data, sending them to each registered serving node
   that supports the Monitoring event service; on receiving an IDA carrying
   Monitoring-Event-Report AVP(s), the HSS shall forward them to the associated
   SCEF.
10. When no SCEF request and no Suggested-Network-Configuration Active Time apply,
    the HSS may send an O&M-configured desired Active Time in the Active-Time AVP.
11. If ProSe, V2X, Emergency-Info, External-Identifier, Aerial-UE or Core Network
    Restrictions (5GC allowed / not allowed) subscription data has been added or
    modified in the HSS, the HSS shall include the corresponding AVP in the
    Subscription-Data.
12. When receiving an IDA with "SGSN Area Restricted", the HSS shall set the SGSN
    area restricted flag.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | The serving node accepted the data and returned any requested information. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | The IMSI is not known to the serving node. |

## Related procedures

- [[S6A-PROC-DSD]] — the counterpart that removes subscription data from the
  serving node.
- [[S6A-PROC-UL]] — Update Location delivers the full profile; ISD pushes
  incremental changes thereafter.
- [[S6A-PROC-NOT]] — the serving node reports UE reachability via Notification when
  ISD requested it.

## Spec references

- TS 29.272, clause 5.2.2.1 (Insert Subscriber Data): General 5.2.2.1.1, HSS
  behaviour 5.2.2.1.3.
- TS 29.272, clause 7.2.9 (IDR) and 7.2.10 (IDA); command code 319 (Table 7.2.2/1).
- TS 29.272, clause 7.3.103 (IDR-Flags), 7.3.47 (IDA-Flags).

## Support status

**Status:** implemented (pragmatic core) — Cycle ⑤ 2026-06-09.

(Informative.) The HSS can push a registered subscriber's current Subscription-Data to
its serving MME via IDR and absorb the IDA.

**Implemented**

- IDR/IDA (command code 319) added to the S6a Diameter dictionary, together with
  IDR-Flags (AVP 1490) and IDA-Flags (AVP 1491).
- `udr_diameter_codec:idr_request/1` builds the IDR AVPs (User-Name,
  Destination-Host/Realm, Subscription-Data via the shared `subscription_data/1`
  builder).
- `udr_diameter_s6a:originate/3` — reusable HSS-initiated outbound helper; Cancel
  Location was refactored onto it and it is ready for DSR/RSR as well.
- `udr_hss:insert_subscriber_data/1` — decides the push: registered and non-purged
  subscriber returns an `insert_subscriber_data` effect carrying the current
  Subscription-Data; otherwise `{error, not_registered}`.
- `udr_diameter_s6a:push_subscriber_data/1` — public trigger that originates the IDR
  to the serving MME (fire-and-forget; the IDA is absorbed).

**Deferred (backlog)**

- Automatic invocation from the provisioning API (subscription-data PUT auto-push IDR)
  — capability is exposed via `push_subscriber_data/1` for operator or future
  automation use; the auto-push is a planned follow-up.
- All IDR-Flags request semantics: UE-Reachability-Request, T-ADS-Data-Request,
  EPS-User-State-Request, EPS-Location-Information-Request, Current-Location-Request,
  Local-Time-Zone-Request, RAT-Type-Requested, Remove-SMS-Registration,
  P-CSCF-Restoration-Request.
- Reset-IDs in IDR.
- Monitoring-Event-Configuration / Monitoring-Event-Report forwarding to SCEF.
- Active-Time (Suggested-Network-Configuration / O&M-configured).
- ProSe, V2X, Emergency-Info, External-Identifier, Aerial-UE, and
  Core-Network-Restrictions subscription data push.
- IDA-Flags processing (e.g. SGSN Area Restricted → set flag in HSS).
- Supported-Features negotiation.

**Tests:** `apps/udr_hss/test/udr_hss_isd_SUITE.erl` (3 cases:
`insert_subscriber_data_registered`, `insert_subscriber_data_not_registered`,
`insert_subscriber_data_purged`); IDR/IDA codec cases in
`apps/udr_diameter/test/udr_diameter_codec_SUITE.erl` (`idr_roundtrip`, `ida_roundtrip`,
`idr_request`); on-wire `idr` case in
`apps/udr_diameter/test/udr_diameter_SUITE.erl`.
