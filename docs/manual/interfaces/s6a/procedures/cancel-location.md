---
id: S6A-PROC-CL
name: Cancel Location
spec: 3GPP TS 29.272
spec_clause: "5.2.1.2"
category: Location Management
initiator: HSS
peer: MME
maps_to:
  - request: Cancel-Location-Request (CLR)
    answer:  Cancel-Location-Answer (CLA)
    command_code: 317
    application_id: 16777251   # S6a/S6d
support_status: implemented      # pragmatic core; assessed 2026-06-09
---

# S6A-PROC-CL — Cancel Location

> [!NOTE]
> Abbreviations: HSS (Home Subscriber Server), MME (Mobility Management Entity),
> SGSN (Serving GPRS Support Node), IMSI (International Mobile Subscriber
> Identity), UE (User Equipment), AVP (Attribute-Value Pair). This is an
> HSS-initiated procedure: the HSS is the request sender, the MME (S6a) or SGSN
> (S6d) is the request receiver.

## Purpose

(Informative.) The Cancel Location procedure deletes a subscriber record from the
MME or SGSN. The HSS invokes it:

- to inform the MME or SGSN of the subscriber's subscription withdrawal, of a
  profile change that no longer allows PS services, or of a Core Network
  Restrictions change that no longer allows access to EPC;
- to inform the MME or SGSN of an ongoing update procedure (i.e. MME or SGSN
  change);
- to inform the MME or SGSN of an initial attach procedure.

> [!NOTE]
> In a combined HSS+UDM deployment, the HSS+UDM also uses Cancel Location when it
> detects that the UE has moved to a new AMF area and the AMF asks it to cancel the
> MME and/or SGSN registration (see TS 29.563, clause 5.4.2.2).

## Trigger

The HSS invokes the procedure when:

- the subscriber's subscription is withdrawn by the operator; or
- the HSS detects that the UE has moved to a new MME or SGSN area (typically as a
  consequence of [[S6A-PROC-UL]]); or
- an initial attach by the UE requires cancelling a stale registration.

## Participants

| Role | Node | Responsibility |
|---|---|---|
| Initiator | HSS | Sends CLR with the IMSI and a Cancellation-Type to the affected serving node. |
| Peer | MME (S6a) / SGSN (S6d) | Deletes the subscriber record (except for "Initial Attach Procedure") and answers with CLA. |

## Diameter mapping

Request → Answer: **Cancel-Location-Request (CLR) → Cancel-Location-Answer (CLA)**,
command code **317**, Application-Id **16777251** (S6a/S6d).

CLR (request) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| User-Name | (M) | The subscriber IMSI. |
| Cancellation-Type | (M) | MME-Update-Procedure, SGSN-Update-Procedure, Subscription-Withdrawal, Update-Procedure-IWF, or Initial-Attach-Procedure. |
| CLR-Flags | (O) | Bit mask: S6a/S6d-Indicator (bit 0), which selects the affected part of a combined MME/SGSN; Reattach-Required (bit 1), which requests the serving node to make the UE re-attach immediately. |
| Supported-Features | (O) | Features supported by the origin host. |

> [!NOTE]
> Release 16 adds the Reattach-Required flag (bit 1) to CLR-Flags. The HSS may set
> it with a "Subscription Withdrawal" cancellation to force an immediate re-attach,
> and may also use it when withdrawing an Aerial UE subscription.

CLA (answer) key AVPs:

| AVP | Cat. | Carries |
|---|---|---|
| Result-Code / Experimental-Result | (M) | Outcome of the operation. |
| Supported-Features | (O) | Features supported by the serving node. |

## Procedure steps

> [!IMPORTANT]
> Cancel Location is HSS-initiated. The normative receiver-side behaviour belongs
> to the MME or SGSN; the steps below describe the HSS sender role, which is the
> role this catalog tracks.

The HSS-side behaviour:

1. The HSS shall invoke this procedure when the subscriber's subscription is
   withdrawn by the operator, when it detects that the UE has moved to a new MME
   or SGSN area, and when EPC access is no longer allowed due to Core Network
   Restrictions.
2. The HSS shall include Cancellation-Type `Subscription Withdrawal` when the
   subscription is withdrawn by the operator, when the profile no longer allows PS
   services, or when Core Network Restrictions no longer allow access to EPC; the
   HSS may set the Reattach-Required flag in CLR-Flags to request an immediate
   re-attach of the UE.
3. The HSS shall include Cancellation-Type `MME Update Procedure` when the UE has
   moved to a new MME area, and `SGSN Update Procedure` when the UE has moved to a
   new SGSN area.
4. The HSS shall include Cancellation-Type `Initial Attach Procedure` when the
   cancel location is initiated due to an initial attach from the UE.
5. When the cancel location is sent to a combined MME/SGSN during an initial attach
   procedure, the HSS shall include CLR-Flags with the S6a/S6d-Indicator flag set
   to identify the affected part of the combined node.

> [!NOTE]
> Receiver behaviour (informative): if the IMSI is unknown the MME/SGSN returns
> `DIAMETER_SUCCESS`; if the Cancellation-Type is "Initial Attach Procedure" the
> serving node does not delete the subscription data.

## Errors and results

| Result / Experimental-Result | Value | Meaning in this procedure |
|---|---|---|
| DIAMETER_SUCCESS | 2001 | The serving node processed the cancellation (including the case where the IMSI was unknown to it). |

> [!NOTE]
> The CLA answer table (Table 5.2.1.2.1/2) in Release 16 defines only the
> base-protocol Result-Code; no S6a/S6d Experimental-Result-Code is listed as
> applicable to this command. Verified against TS 29.272 V16.8.0.

## Related procedures

- [[S6A-PROC-UL]] — Update Location at a new serving node causes the HSS to send a
  Cancel Location to the previous serving node.
- [[S6A-PROC-PU]] — Purge UE is the serving-node-initiated counterpart that clears
  a registration.

## Spec references

- TS 29.272, clause 5.2.1.2 (Cancel Location): General 5.2.1.2.1, HSS behaviour
  5.2.1.2.3.
- TS 29.272, clause 7.2.7 (CLR) and 7.2.8 (CLA); command code 317 (Table 7.2.2/1).
- TS 29.272, clause 7.3.24 (Cancellation-Type), 7.3.152 (CLR-Flags).

## Support status

**Status:** implemented (pragmatic core) — Cycle ① 2026-06-09.

(Informative.) The HSS-initiated send path works end to end — Update Location triggers
a real CLR over the wire with the correct Cancellation-Type and the CLA is accepted.

> [!NOTE]
> The prior Cancellation-Type bug (hardcoded `Subscription Withdrawal (2)`) was fixed
> in Cycle ①.

**Implemented**

- CLR is built (`apps/udr_diameter/src/udr_diameter_codec.erl:81`, `clr_request/1`) and
  sent fire-and-forget over the wire (`apps/udr_diameter/src/udr_diameter_s6a.erl:128`,
  `diameter:call(..., ['CLR'|Clr], [detach,...])`), driven by the `cancel_location`
  effect emitted from Update Location (`apps/udr_hss/src/udr_hss.erl:61`).
- Correct Cancellation-Type, derived per trigger by the Update Location flow:
  `MME Update Procedure (0)` for an inter-MME move; `Initial Attach Procedure (4)`
  when the Initial-Attach-Indicator flag is set. Mapped to the wire value via the
  private `cancellation_type/1` function in `udr_diameter_codec:clr_request/1`.
- HSS-originated CLR sent on the wire and CLA accepted.

**Deferred (backlog)**

- CLR-Flags AVP: S6a/S6d-Indicator (step 5) and Reattach-Required (Rel-16) absent
  from dictionary and code.
- CLA result-driven retry / alarm: CLA is accepted but the Result-Code is not
  processed further.
- Non-ULR triggers: subscription withdrawal, profile change, CN-restriction change,
  and standalone initial-attach triggers (steps 1, 2, 4) have no path.
- Supported-Features not handled.

**Tests:** `apps/udr_diameter/test/udr_diameter_SUITE.erl` (`ulr_then_clr` — on-wire
CLR + CLA, asserts Cancellation-Type 0 via `udr_diameter_test_mme:recorded_clr/1`),
`apps/udr_diameter/test/udr_diameter_codec_SUITE.erl` (`clr_request`, `clr_roundtrip`),
`apps/udr_hss/test/udr_hss_ulr_SUITE.erl` (`ulr_new_mme_emits_cancel_location`,
`ulr_initial_attach_uses_initial_attach_cancellation`).
