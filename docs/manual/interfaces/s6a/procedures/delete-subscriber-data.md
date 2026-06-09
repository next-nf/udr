---
id: S6A-PROC-DSD
name: Delete Subscriber Data
spec: 3GPP TS 29.272
spec_clause: "5.2.2.2"
category: Subscriber Data Handling
initiator: HSS
peer: MME
maps_to:
  - request: Delete-Subscriber-Data-Request (DSR)
    answer:  Delete-Subscriber-Data-Answer (DSA)
    command_code: 320
    application_id: 16777251   # S6a/S6d
support_status: unevaluated      # filled in a later step
---

# S6A-PROC-DSD — Delete Subscriber Data

> [!NOTE]
> Abbreviations: HSS (Home Subscriber Server), MME (Mobility Management Entity),
> SGSN (Serving GPRS Support Node), UE (User Equipment), IMSI (International
> Mobile Subscriber Identity), APN (Access Point Name), AVP (Attribute-Value
> Pair), EPS (Evolved Packet System), PDN (Packet Data Network), SRVCC (Single
> Radio Voice Call Continuity), STN-SR (Session Transfer Number for SRVCC). This
> is an HSS-initiated procedure on S6a (HSS↔MME) and S6d (HSS↔SGSN).

## Purpose

(Informative.) The Delete Subscriber Data procedure removes part of the HSS user
profile that is stored in the MME or SGSN. The HSS invokes it to remove:

- all or a subset of the EPS subscription data (APN Configuration Profile);
- the regional subscription;
- the subscribed charging characteristics;
- the Session Transfer Number for SRVCC (STN-SR);
- trace data;
- ProSe subscription data;
- Reset-IDs;
- the MSISDN;
- the UE Usage Type;
- V2X subscription data;
- External Identifier(s).

> [!NOTE]
> Release 16 expands the set of withdrawable data classes well beyond the Rel-11
> list. The full DSR-Flags bit map now extends to bit 31 and covers, among others,
> ProSe, Reset-IDs, MSISDN, UE Usage Type, V2X, External-Identifier, Aerial UE,
> Paging Time Window, Active Time, eDRX Cycle Length, and Service Gap Time
> withdrawals.

## Trigger

The HSS invokes the procedure when subscription data that was previously delivered
to the serving node is withdrawn and the stored copy needs to be removed.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | HSS | Sends DSR with DSR-Flags identifying which data classes to remove. |
| Peer | MME (S6a) / SGSN (S6d) | Deletes the indicated data, applies the consequent local actions, and answers with DSA. |

## Diameter mapping

Request → Answer: **Delete-Subscriber-Data-Request (DSR) →
Delete-Subscriber-Data-Answer (DSA)**, command code **320**, Application-Id
**16777251** (S6a/S6d).

DSR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| DSR-Flags | (M) | Bit mask (bits 0–31) identifying the data classes to withdraw (e.g. regional subscription, complete/partial APN configuration, charging characteristics, STN-SR, trace, CSG, APN-OI-Replacement, GMLC list, LCS, SMS, RAU/TAU timer, vSRVCC, A-MSISDN, ProSe, Reset-IDs, MSISDN, UE Usage Type, V2X, External-Identifier). |
| Trace-Reference | (C) | Present when the "Trace Data Withdrawal" bit is set; identifies the Trace Session. |
| Context-Identifier | (C) | Present when "PDN subscription contexts Withdrawal" or "PDP context withdrawal" is set; shall not be the default APN. |
| TS-Code / SS-Code | (C) | Teleservice / supplementary-service codes to delete (SMS/LCS withdrawal). |
| SCEF-Id | (C) | Identity of the SCEF whose Monitoring events are to be deleted; present when the "Delete monitoring events" bit is set. |
| eDRX-Related-RAT | (C) | RAT types whose eDRX Cycle Lengths are to be deleted; used with the "eDRX-Cycle-Length-Withdrawal" bit. |
| External-Identifiers | (O) | External Identifier(s) to delete; used with the "External-Identifier-Withdrawal" bit. |
| Supported-Features | (O) | Features supported by the origin host. |

DSA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome; the only applicable Experimental-Result is User Unknown. |
| DSA-Flags | (C) | Bit mask of answer indications (e.g. SGSN Area Restricted). |
| Supported-Features | (O) | Features supported by the serving node. |

## Procedure steps

> [!IMPORTANT]
> Delete Subscriber Data is HSS-initiated. The steps below describe the HSS sender
> role, which is the role this catalog tracks. Receiver-side validation (e.g.
> returning User Unknown, or rejecting deletion of the default APN) is performed by
> the MME/SGSN.

The HSS-side behaviour:

1. The HSS shall use this procedure to remove deleted subscription data from the
   MME or SGSN.
2. The HSS shall use this procedure to remove deleted GPRS Subscription Data from
   the SGSN or combined MME/SGSN when the GPRS-Subscription-Data-Indicator was
   previously received as set in the ULR-Flags during Update Location.
3. The HSS shall not set the "Complete APN Configuration Profile Withdrawal" bit in
   the DSR-Flags when sending a DSR to an MME, because the default APN shall always
   be present in an MME.
4. When receiving a DSA with "SGSN Area Restricted", the HSS shall set the SGSN
   area restricted flag.

> [!NOTE]
> Receiver behaviour (informative): if the IMSI is unknown the MME/SGSN returns
> `DIAMETER_ERROR_USER_UNKNOWN`; an attempt to delete the default APN, or a
> "Complete APN Configuration Profile Withdrawal" at an MME, is rejected with
> `DIAMETER_UNABLE_TO_COMPLY`.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | The serving node deleted the indicated data. |
| DIAMETER_ERROR_USER_UNKNOWN | 5001 | The IMSI is not known to the serving node. |
| DIAMETER_UNABLE_TO_COMPLY | 5012 | The serving node could not delete the data (e.g. default-APN context, or a database error). |

## Related procedures

- [[S6A-PROC-ISD]] — the counterpart that adds or replaces subscription data.
- [[S6A-PROC-UL]] — Update Location delivers the full profile that DSD later trims.

## Spec references

- TS 29.272, clause 5.2.2.2 (Delete Subscriber Data): General 5.2.2.2.1, HSS
  behaviour 5.2.2.2.3.
- TS 29.272, clause 7.2.11 (DSR) and 7.2.12 (DSA); command code 320 (Table 7.2.2/1).
- TS 29.272, clause 7.3.25 (DSR-Flags), 7.3.26 (DSA-Flags).

## Support status

_Not yet evaluated. To be completed in a later step._
