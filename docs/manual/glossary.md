# Terms and Abbreviations

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This is the canonical glossary for the HSS operator manual. Every other document in the manual links here rather than redefining a term. Each entry expands the abbreviation and defines the term in this system's terms. Entries are definitions only; they carry no requirements.

> [!NOTE]
> Two unrelated meanings of **AMF** appear in this domain. Both are used in this system and both are listed below as separate entries: **AMF (Access and Mobility Management Function)**, a 5G core network function, and **AMF (Authentication Management Field)**, a field inside the AKA authentication token. Check which one a document means from its context.

Entries are ordered alphabetically.

| Term | Definition |
| --- | --- |
| **3GPP** | Third Generation Partnership Project. The standards body whose specifications define the EPC, the 5G core, and the interfaces (S6a, Cx, Nudr) that this system implements. |
| **AIA** | Authentication-Information-Answer. The S6a Diameter answer returned in response to an AIR; it carries the requested EPS authentication vectors. |
| **AGPL-3.0** | GNU Affero General Public License, version 3. The free-software license under which this system is distributed (see the `LICENSE` file at the repository root). Its network-use clause obliges an operator who modifies the software and offers it as a network service to make the modified source available to the users of that service. |
| **AIR** | Authentication-Information-Request. The S6a Diameter command an MME sends to the HSS to obtain EPS authentication vectors for a subscriber. |
| **AMF (Access and Mobility Management Function)** | The 5G core network function that handles registration, connection, and mobility management for a UE. In this system it is the consumer of the SBI registration context exposed under the `amf-3gpp-access` resource. This is distinct from the Authentication Management Field below. |
| **AMF (Authentication Management Field)** | A 2-byte field carried inside the AUTN token of an AKA authentication vector and used as an input to the MILENAGE f1 function. In this system it is supplied per subscriber in the provisioning payload (the `amf` field). This is distinct from the Access and Mobility Management Function above. |
| **AUTN** | Authentication Token. A value in an EPS authentication vector, sent to the UE so that the UE can authenticate the network. It is built from the sequence number (concealed by an anonymity key), the Authentication Management Field, and a message authentication code. |
| **Authentication vector (AV)** | The set of values the HSS generates for one authentication run of a subscriber. For EPS-AKA it comprises RAND, XRES, AUTN, and the derived key material. The HSS returns authentication vectors in an AIA. |
| **AV** | See Authentication vector. |
| **AVP** | Attribute-Value Pair. The basic data element of a Diameter message; each AVP carries one attribute, such as an identity or a result code, within a command. |
| **BEAM** | Bogdan/Björn's Erlang Abstract Machine. The virtual machine that executes compiled Erlang/OTP code and runs this system. |
| **CEA** | Capabilities-Exchange-Answer. The Diameter answer a peer returns in response to a CER during the capability-exchange handshake that opens a Diameter connection. |
| **CER** | Capabilities-Exchange-Request. The Diameter request a peer sends to open a connection and negotiate the supported applications; the HSS answers it with a CEA. |
| **CLA** | Cancel-Location-Answer. The S6a Diameter answer returned in response to a CLR. |
| **CLR** | Cancel-Location-Request. An HSS-initiated S6a Diameter command that tells a previously registered MME to cancel a subscriber's location, for example when the subscriber re-registers through a different MME. |
| **Cx** | The Diameter interface between an IMS Call Session Control Function and the HSS, used for IMS subscriber authentication and registration. It is named here because the HSS role and the IMS identities (IMPI, IMPU) relate to it. |
| **Diameter** | The Authentication, Authorization, and Accounting signaling protocol (IETF RFC 6733) used by the EPC. The S6a interface between the MME and the HSS runs over Diameter. |
| **eNB** | E-UTRAN Node B. The 4G/LTE base station that provides the radio link to the UE and connects to the MME. |
| **epmd** | Erlang Port Mapper Daemon. The Erlang/OTP name-resolution service for distributed nodes; it listens on TCP port `4369` and lets nodes find one another's distribution ports. Cluster formation depends on it. |
| **EPC** | Evolved Packet Core. The 4G/LTE core network. The HSS is the subscriber database of the EPC, reached by the MME over the S6a interface. |
| **EPS-AKA** | Evolved Packet System Authentication and Key Agreement. The mutual authentication and key-agreement procedure used in LTE, for which the HSS generates EPS authentication vectors. |
| **Erlang/OTP** | The programming language (Erlang) together with its standard libraries and framework (OTP, Open Telecom Platform) in which this system is written. |
| **ETS** | Erlang Term Storage. The in-memory term store built into Erlang/OTP. It is the default data backend of this system, requiring no external database. |
| **gNB** | Next Generation Node B. The 5G base station that provides the radio link to the UE and connects to the 5G core. |
| **HSS** | Home Subscriber Server. The 3GPP subscriber database for the EPC. It stores subscriber profiles and authentication credentials and serves the MME over S6a. This system implements the HSS role. |
| **HTTP** | Hypertext Transfer Protocol. The application protocol over which the SBI and the provisioning API are served. In this system both listeners serve cleartext HTTP; neither terminates TLS. |
| **IMS** | IP Multimedia Subsystem. The 3GPP architecture for delivering IP-based multimedia services, in which the HSS authenticates subscribers over the Cx interface using the IMPI and IMPU identities. |
| **IMPI** | IP Multimedia Private Identity. The private identity used to authenticate a subscriber in the IMS, carried over the Cx interface. |
| **IMPU** | IP Multimedia Public Identity. The public identity by which other users reach a subscriber in the IMS; a subscriber may have several. |
| **IMSI** | International Mobile Subscriber Identity. The globally unique identifier of a subscriber on the mobile network. It is the primary key by which subscribers are provisioned and looked up in this system. |
| **KASME** | The Access Security Management Entity key. A 32-byte key derived during EPS-AKA and returned as part of each E-UTRAN authentication vector; the MME uses it to derive the subordinate NAS and AS keys. |
| **Ki** | The subscriber's permanent secret authentication key (denoted K in 3GPP), shared between the HSS and the UE's SIM and used as an input to MILENAGE. It is provisioned per subscriber. |
| **LTE** | Long-Term Evolution. The 4G radio access and system technology served by the EPC, for which the HSS provides EPS-AKA authentication and subscription data. |
| **MILENAGE** | The 3GPP example algorithm set (TS 35.205/206) for AKA authentication, based on a block cipher and built from functions f1–f5. This system uses MILENAGE to generate EPS authentication vectors. |
| **MME** | Mobility Management Entity. The EPC control-plane node that manages UE attachment and mobility. It is the S6a peer that sends AIR, ULR, and PUR to the HSS. |
| **MongoDB** | A document-oriented database. It is the optional persistent data backend of this system, selectable in place of the default ETS backend. |
| **Nudr (Nudr-DR)** | The Service-Based Interface that the 5G UDR exposes for subscriber data, defined by 3GPP. This system exposes a Nudr-flavoured data-repository (DR) interface under `/nudr-dr/v1/subscription-data`. |
| **OP** | Operator Variant Algorithm Configuration Field. An operator-specific value used by MILENAGE. With Ki it derives OPc. It may be provisioned in place of OPc. |
| **OPc** | The operator variant value derived from OP and Ki, used directly by MILENAGE during authentication. It may be provisioned per subscriber instead of OP. |
| **OpenTelemetry** | The open observability framework for traces, metrics, and logs. This system is instrumented with OpenTelemetry across its Diameter and HTTP paths. |
| **OTLP** | OpenTelemetry Protocol. The wire protocol by which OpenTelemetry traces and metrics are exported to a collector. |
| **PUA** | Purge-UE-Answer. The S6a Diameter answer returned in response to a PUR. |
| **PUR** | Purge-UE-Request. The S6a Diameter command an MME sends to the HSS to mark a UE as purged from the MME. |
| **RAND** | Random Challenge. The random value in an authentication vector, sent to the UE; the UE and the HSS each compute a response from it during AKA. |
| **rebar3** | The build tool for Erlang/OTP projects. This system is built and tested with rebar3. |
| **relx** | The release assembler used by rebar3 to package an Erlang/OTP release of this system for deployment. |
| **S6a** | The Diameter interface between the MME and the HSS in the EPC, carrying AIR/AIA, ULR/ULA, PUR/PUA, and CLR/CLA. It is the primary signaling interface this system serves. |
| **SBI** | Service-Based Interface. The HTTP/2-based interface style of the 5G core, over which network functions expose services. This system exposes the Nudr-DR service over an SBI. |
| **SQN** | Sequence Number. A per-subscriber counter used in AKA to let the UE verify that an authentication vector is fresh and to detect replay. The HSS maintains it and the UE can request resynchronization when it falls out of range. |
| **SUPI** | Subscription Permanent Identifier. The permanent subscriber identifier in the 5G core, the 5G counterpart of the IMSI. |
| **`syn`** | An Erlang/OTP process registry and process-group library. This system uses `syn` to coordinate per-IMSI session locking across cluster nodes so that concurrent signaling for one subscriber serializes correctly. |
| **TCP** | Transmission Control Protocol. The transport over which every listener in this system runs: the S6a Diameter listener, the SBI HTTP listener, and the provisioning HTTP listener. None of them is wrapped in TLS by this system. |
| **TLS** | Transport Layer Security. The protocol that provides encryption and peer authentication for a TCP connection. This system terminates no TLS on any listener; transport confidentiality, where required, is provided by network-level controls. |
| **UDM** | Unified Data Management. The 5G core network function that handles subscriber data management and authentication credential generation. This system provides the UDM role alongside the HSS and UDR. |
| **UDR** | Unified Data Repository. The 5G core network function that stores subscriber and policy data and serves it over the Nudr interface. This system provides the UDR role. |
| **UE** | User Equipment. The subscriber device (for example a handset with its SIM) that attaches to the network and is authenticated using credentials held by the HSS. |
| **ULA** | Update-Location-Answer. The S6a Diameter answer returned in response to a ULR; it carries the subscriber's subscription data. |
| **ULR** | Update-Location-Request. The S6a Diameter command an MME sends to the HSS to register itself as the serving MME for a subscriber and to obtain subscription data. |
| **XRES** | Expected Response. The value in an authentication vector that the HSS expects the UE to compute and return; the network compares the UE's response against XRES to authenticate the UE. |
