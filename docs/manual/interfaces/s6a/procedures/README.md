# S6a HSS procedures — reference catalog

This directory catalogs the conceptual S6a procedures defined in **3GPP TS 29.272
clause 5** ("MME – HSS (S6a) and SGSN – HSS (S6d)"), documenting each from the
**HSS role**. Each procedure maps to one Diameter command pair on the S6a/S6d
application (Application-Id **16777251**). One file per procedure records its
purpose, trigger, Diameter mapping, normative HSS-side steps, and result codes;
the per-file `support_status` tracks whether this codebase implements it. The
verbatim 3GPP text is published as **ETSI TS 129 272** (for example
[ETSI TS 129 272 V16.8.0](https://www.etsi.org/deliver/etsi_ts/129200_129299/129272/16.08.00_60/ts_129272v160800p.pdf)).

This catalog is grounded on **3GPP TS 29.272 Release 16** (V16.8.0, 2024-09),
published verbatim as ETSI TS 129 272 V16.x.x.

> [!NOTE]
> Diameter base peer/session management (CER/CEA, DWR/DWA, DPR/DPA) is **out of
> scope** here — that is IETF RFC 6733, not TS 29.272 clause 5. The ME Identity
> Check procedure (ECR/ECA) is also out of scope: it is defined in clause 6 on the
> S13/S13' interface (MME/SGSN ↔ EIR), not on S6a.

## Procedures

The clause-5 procedure list is unchanged from earlier releases: Release 16 defines
exactly these eight S6a/S6d procedures, with the same command codes.

| ID | Procedure | Clause | Initiator | Diameter mapping (code) | Support status | File |
|---|---|---|---|---|---|---|
| S6A-PROC-UL | Update Location | 5.2.1.1 | MME / SGSN | ULR/ULA (316) | partial | [update-location.md](update-location.md) |
| S6A-PROC-CL | Cancel Location | 5.2.1.2 | HSS | CLR/CLA (317) | partial | [cancel-location.md](cancel-location.md) |
| S6A-PROC-PU | Purge UE | 5.2.1.3 | MME / SGSN | PUR/PUA (321) | partial | [purge-ue.md](purge-ue.md) |
| S6A-PROC-ISD | Insert Subscriber Data | 5.2.2.1 | HSS | IDR/IDA (319) | not-implemented | [insert-subscriber-data.md](insert-subscriber-data.md) |
| S6A-PROC-DSD | Delete Subscriber Data | 5.2.2.2 | HSS | DSR/DSA (320) | not-implemented | [delete-subscriber-data.md](delete-subscriber-data.md) |
| S6A-PROC-AIR | Authentication Information Retrieval | 5.2.3.1 | MME / SGSN | AIR/AIA (318) | partial | [authentication-information-retrieval.md](authentication-information-retrieval.md) |
| S6A-PROC-RST | Reset | 5.2.4.1 | HSS | RSR/RSA (322) | not-implemented | [reset.md](reset.md) |
| S6A-PROC-NOT | Notification | 5.2.5.1 | MME / SGSN | NOR/NOA (323) | not-implemented | [notification.md](notification.md) |

> [!NOTE]
> `support_status` was assessed on 2026-06-09 against the code at `main` (c605b66):
> four procedures are **partial** (AIR, Update Location, Purge UE, Cancel Location)
> and four are **not-implemented** (Insert/Delete Subscriber Data, Reset,
> Notification). Each file's "Support status" section records the evidence
> (entry points, what is implemented, and gaps). Values:
> `partial` · `not-implemented` (a future `implemented` is reserved for full coverage).

## Category grouping (TS 29.272 clause 5.2)

- **5.2.1 Location Management Procedures** — Update Location, Cancel Location, Purge UE
- **5.2.2 Subscriber Data Handling Procedures** — Insert Subscriber Data, Delete Subscriber Data
- **5.2.3 Authentication Procedures** — Authentication Information Retrieval
- **5.2.4 Fault Recovery Procedures** — Reset
- **5.2.5 Notification Procedures** — Notification
