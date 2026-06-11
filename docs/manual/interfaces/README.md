# Interface References

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This directory holds one interface reference per external interface of the `udr` project. Each reference documents the contract of one interface: the operations it exposes, the request and response shapes, and every status or result code the implementation actually returns.

This index is informative. The references it links to carry the normative interface contracts.

> [!NOTE]
> An interface reference documents *what the code implements*. Where a field, operation, or code could not be confirmed against the source, the reference says so rather than describing behavior that does not exist. The configuration of each listener (bind address, port, Diameter identity) is documented separately in the matching [configuration reference](../configuration/README.md).

## 1. References

| Reference | Application | Interface | Default endpoint |
| --- | --- | --- | --- |
| [S6a Diameter](s6a.md) | `udr_diameter` | The [S6a](../glossary.md) [Diameter](../glossary.md) interface between the [MME](../glossary.md) and the [HSS](../glossary.md): AIR/AIA, ULR/ULA, PUR/PUA, and HSS-initiated CLR/CLA. | TCP `127.0.0.1:3868` |
| [SBI (Nudr-DR)](sbi.md) | `udr_sbi` | The [Nudr](../glossary.md)-flavored 5G [SBI](../glossary.md) data-repository: read authentication-subscription and am-data, and read/write the amf-3gpp-access registration context. | HTTP `127.0.0.1:8080` |
| [Provisioning API](provisioning.md) | `udr_api` | The admin provisioning HTTP API: create, read, and delete a subscriber by [IMSI](../glossary.md). | HTTP `127.0.0.1:8090` |

## 2. Relationship to the rest of the manual

- The endpoints above are the *defaults*. Changing the bind address, port, or Diameter identity is configuration, covered in the [configuration references](../configuration/README.md).
- All three interfaces reach subscriber data through the same `udr_data` seam, as described in the [architecture overview](../overview.md).
- Terms and abbreviations (HSS, MME, AMF, S6a, SBI, Nudr, IMSI, AIR, ULR, PUR, CLR, AVP, Ki, OPc) are defined once in the [glossary](../glossary.md).

> [!CAUTION]
> Two of these interfaces return or accept long-term secret key material in clear and perform no authentication of the caller. The provisioning API ([provisioning.md](provisioning.md)) is unauthenticated, and the SBI authentication-subscription resource ([sbi.md](sbi.md)) returns [Ki](../glossary.md) and [OPc](../glossary.md) in clear hex. Each reference flags this where it applies; the listeners `shall` be bound only to trusted interfaces.
