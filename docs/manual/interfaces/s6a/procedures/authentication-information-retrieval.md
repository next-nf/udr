---
id: S6A-PROC-AIR
name: Authentication Information Retrieval
spec: 3GPP TS 29.272
spec_clause: "5.2.3.1"
category: Authentication
initiator: MME
peer: HSS
maps_to:
  - request: Authentication-Information-Request (AIR)
    answer:  Authentication-Information-Answer (AIA)
    command_code: 318
    application_id: 16777251   # S6a/S6d
support_status: unevaluated      # filled in a later step
---

# S6A-PROC-AIR — Authentication Information Retrieval

> [!NOTE]
> Abbreviations: MME (Mobility Management Entity), SGSN (Serving GPRS Support
> Node), HSS (Home Subscriber Server), AuC (Authentication Centre), IMSI
> (International Mobile Subscriber Identity), AV (Authentication Vector), AVP
> (Attribute-Value Pair), AKA (Authentication and Key Agreement), E-UTRAN
> (Evolved UTRAN), UTRAN/GERAN (UMTS/GSM EDGE Radio Access Network), KASME (Key
> for Access Security Management Entity), PLMN (Public Land Mobile Network),
> AUTS (re-synchronisation token). The MME drives this on S6a; the SGSN drives
> the equivalent on S6d.

## Purpose

(Informative.) The Authentication Information Retrieval procedure lets the MME or
SGSN obtain authentication vectors from the HSS, so it can run AKA with the UE.
The HSS generates the vectors via the AuC and, for E-UTRAN, derives KASME bound to
the visited PLMN before returning them.

## Trigger

The MME or SGSN invokes the procedure when it needs authentication vectors — at
attach, tracking-area/routing-area update, or service request — or after an AKA
synchronisation failure, in which case it includes the re-synchronisation
information (AUTS).

> [!NOTE]
> If the MME or SGSN supports emergency services for users in limited service
> state and the user's IMSI is unavailable or marked unauthenticated, it does not
> invoke this procedure.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | MME (S6a) / SGSN (S6d) | Sends AIR requesting E-UTRAN and/or UTRAN/GERAN vectors for the visited PLMN. |
| Peer | HSS | Validates the subscription, drives the AuC to generate vectors, derives KASME for E-UTRAN, and returns the vectors in the AIA. |

## Diameter mapping

Request → Answer: **Authentication-Information-Request (AIR) →
Authentication-Information-Answer (AIA)**, command code **318**, Application-Id
**16777251** (S6a/S6d).

AIR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| Visited-PLMN-Id | (M) | MCC/MNC of the visited PLMN (used to bind KASME). |
| Requested-EUTRAN-Authentication-Info | (C) | Number of E-UTRAN vectors, Immediate-Response-Preferred, and (on resync) the Re-Synchronization-Info. |
| Requested-UTRAN-GERAN-Authentication-Info | (C) | Number of UTRAN/GERAN vectors, Immediate-Response-Preferred, and (on resync) Re-Synchronization-Info. |
| AIR-Flags | (O) | Bit mask: Send UE Usage Type (bit 0), requesting the HSS to return the subscriber's UE Usage Type (Dedicated Core Networks). |
| Supported-Features | (O) | Features supported by the origin host. |

AIA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome. |
| Authentication-Info | (C) | The generated authentication vectors (E-UTRAN and/or UTRAN/GERAN). |
| UE-Usage-Type | (C) | Present when the HSS supports Dedicated Core Networks, "Send UE Usage Type" was set, and the value is in the subscription; returned with `DIAMETER_SUCCESS` or `DIAMETER_AUTHENTICATION_DATA_UNAVAILABLE`. |
| Error-Diagnostic | (O) | Refines the "Unknown EPS Subscription" outcome. |
| Supported-Features | (O) | Features supported by the HSS. |

> [!NOTE]
> Release 16 adds the AIR-Flags AVP (with the "Send UE Usage Type" bit) to the
> request and the UE-Usage-Type AVP to the answer, supporting Dedicated Core
> Network (DCN) selection.

## Procedure steps

On receiving an AIR, the HSS:

1. Check whether subscription data exists for the IMSI. The HSS shall return
   `DIAMETER_ERROR_USER_UNKNOWN` if there is no subscription of any type (EPS,
   GPRS or CS).
2. The HSS shall return `DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION` if the subscriber
   has neither EPS nor GPRS subscription data; it may add Error-Diagnostic
   indicating whether GPRS data is subscribed.
3. If E-UTRAN authentication info is requested, the HSS shall check whether serving
   nodes within the realm identified by the Origin-Realm are allowed to request
   authentication information for use in the serving network identified by the
   Visited-PLMN-Id.
4. The HSS shall request the AuC to generate the requested vectors; subject to load
   and to the Immediate-Response-Preferred indication, it may generate fewer than
   requested.
5. If E-UTRAN authentication info is requested, the HSS shall derive KASME (bound to
   the visited PLMN) before sending the response to the MME or combined MME/SGSN.
6. If the AuC cannot calculate vectors due to an unallowed attachment, the HSS shall
   return `DIAMETER_AUTHORIZATION_REJECTED` and shall not return any vector.
7. Otherwise, if no pre-computed vector is available and the AuC cannot calculate
   vectors due to an unknown failure (e.g. internal database error), the HSS shall
   set the result code to `DIAMETER_AUTHENTICATION_DATA_UNAVAILABLE`.
8. If the Re-Synchronization-Info was received, the HSS shall check the AUTS before
   sending new vectors. If both Requested-EUTRAN and Requested-UTRAN-GERAN AVPs
   carry Re-Synchronization-Info, the HSS shall not check AUTS and shall return
   `DIAMETER_UNABLE_TO_COMPLY` with no vectors.
9. If the HSS supports Dedicated Core Networks and the "Send UE Usage Type" flag is
   set, the HSS shall include the UE-Usage-Type AVP in the answer when the value is
   available in the subscription (with `DIAMETER_SUCCESS` or
   `DIAMETER_AUTHENTICATION_DATA_UNAVAILABLE`); when the flag is set but no
   Immediate-Response-Preferred indication is present, the HSS may return no
   vectors and still return `DIAMETER_SUCCESS`.
10. The HSS shall return `DIAMETER_SUCCESS` and the generated vectors (if any) to
    the MME or SGSN.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | Vectors generated and returned. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | No subscription of any type exists for the IMSI. |
| DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION | 5420 | The subscriber has neither EPS nor GPRS subscription data. |
| DIAMETER_AUTHENTICATION_DATA_UNAVAILABLE | 4181 | Transient failure generating vectors; the requester may retry. |
| DIAMETER_AUTHORIZATION_REJECTED | 5003 | Attachment not allowed (e.g. SIM-only equipment attaching via E-UTRAN); no vectors returned. |
| DIAMETER_UNABLE_TO_COMPLY | 5012 | Both access types carried Re-Synchronization-Info; AUTS not checked, no vectors returned. |

## Related procedures

- [[S6A-PROC-UL]] — Update Location typically follows successful authentication at
  attach.

## Spec references

- TS 29.272, clause 5.2.3.1 (Authentication Information Retrieval): General
  5.2.3.1.1, HSS behaviour 5.2.3.1.3.
- TS 29.272, clause 7.2.5 (AIR) and 7.2.6 (AIA); command code 318 (Table 7.2.2/1).
- TS 29.272, clause 7.3.201 (AIR-Flags), 7.3.202 (UE-Usage-Type).
- TS 29.272, clause 7.4.3.1 (5001), 7.4.3.2 (5420), 7.4.4.1 (4181).

> [!NOTE]
> `DIAMETER_AUTHORIZATION_REJECTED` (5003) and `DIAMETER_UNABLE_TO_COMPLY` (5012)
> are Diameter base-protocol / common 3GPP result codes reused by this procedure;
> they are referenced in the AIR HSS behaviour text (5.2.3.1.3) but their numeric
> values are defined in IETF RFC 6733 / TS 29.229, not in TS 29.272 clause 7.4. The
> values 5003 and 5012 are confirmed against the Result-Code-to-EMM/GMM-cause
> mapping tables in TS 29.272 V16.8.0 (clause 8.x), which cite them by number.

## Support status

_Not yet evaluated. To be completed in a later step._
