# HSS Operator Manual

This manual is the operator-facing documentation for the `udr` project: a converged 3GPP Home Subscriber Server (HSS) and Unified Data Repository / Unified Data Management (UDR/UDM), written in Erlang/OTP. It explains how to install, configure, operate, and troubleshoot the system.

## Who this manual is for

This manual is written for operators and integrators who deploy and run the HSS, and who did not build the system. It states what to configure and do, and how to confirm that each change took effect. It does not document internal implementation; that belongs in the source code and the API documentation.

Familiarity with 3GPP core-network concepts (EPC, S6a, the 5G Service-Based Interface) and with running Erlang/OTP releases is assumed. Terms and abbreviations are defined in the [glossary](glossary.md).

## Documentation standard

Every document in this manual follows the project documentation standard, the `documenting-hss` house standard at [`.claude/skills/documenting-hss/`](../../.claude/skills/documenting-hss/). That standard governs the verbal forms (`shall` / `should` / `may` / `can`), the separation of normative from informative text, the use of GitHub admonitions for asides, American spelling, and the rule that each term is defined once.

> [!NOTE]
> This manual is being written in stages. Every document listed below now exists; each links to its page.

## Contents

| Document | Purpose | Status |
| --- | --- | --- |
| [Terms and Abbreviations](glossary.md) | The shared glossary every other document links to. | Available |
| [Overview](overview.md) | Architecture and data flow across the umbrella applications. | Available |
| [Installation and build](install.md) | Prerequisites and build instructions. | Available |
| [Quickstart](quickstart.md) | From clone to the first authenticated subscriber. | Available |
| [Configuration](configuration/README.md) | One configuration reference per subsystem. | Available |
| [Interfaces](interfaces/README.md) | S6a, SBI, and Provisioning API interface references. | Available |
| [Operations](operations/README.md) | Operational runbooks. | Available |
| [Troubleshooting](troubleshooting/README.md) | Troubleshooting guides, indexed by the symptom you observe. | Available |
| [Diagrams](diagrams/README.md) | Shared deployment, sequence, and state diagrams. | Available |
| [Security](security.md) | Security considerations and hardening guidance. | Available |
| [Compatibility](compatibility.md) | Supported versions and interoperability notes. | Available |
| [Maintenance](maintaining.md) | Keeping the manual accurate as the code evolves: the change-impact map, versioning, and pre-merge checks. | Available |

## How the manual is organized

The glossary is the canonical source of terms and abbreviations; every other document links to it rather than redefining a term. The `configuration/`, `interfaces/`, `operations/`, and `troubleshooting/` directories each hold one document per subsystem or task, following the matching template from the documentation standard. Shared diagrams live under `diagrams/` so that several documents can reference the same figure. The [security](security.md) and [compatibility](compatibility.md) pages sit at the top level alongside the overview.
