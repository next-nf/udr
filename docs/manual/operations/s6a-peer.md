# Operations Runbook: Connect and Verify an MME (S6a Peer)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers the HSS-side configuration and verification needed for an external [MME](../glossary.md) to connect over [S6a](../glossary.md) [Diameter](../glossary.md): binding the listener to a routable address, presenting the right Diameter identity, confirming the capability exchange (CER/CEA), and confirming an [AIR](../glossary.md) is served. It is for operators integrating the HSS with an MME (or a Diameter test client).

> [!IMPORTANT]
> The Diameter peer itself — a real MME or a Diameter test client that originates the CER and the AIR — is **out of scope** of this runbook and is not provided by this project. An open-source EPC such as Open5GS includes an MME that speaks S6a and `may` be used as the peer; this is an example only, and no tested integration is claimed. This runbook documents what the HSS side `shall` provide and how to confirm it; the peer is configured and operated separately.

The S6a message contract (the AVPs of AIR/AIA, ULR/ULA, PUR/PUA, CLR/CLA and the result codes) is defined in the [S6a interface reference](../interfaces/s6a.md). The `udr_diameter` parameters are defined in the [S6a Diameter configuration reference](../configuration/diameter.md).

---

## RUN-S6A-PEER-001: Bind the S6a listener and verify CER/CEA and AIR

### Purpose

*(Informative.)* This procedure makes the HSS reachable to an external MME on the S6a interface and confirms, in order, that the listener is bound, that a peer's capability exchange succeeds (CEA carrying the HSS Origin-Host), and that an AIR for a provisioned subscriber returns authentication vectors. An operator runs it when bringing an MME into service against the HSS.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node is running, per [`RUN-LIFECYCLE-001`](lifecycle.md).
- At least one subscriber is provisioned with the [IMSI](../glossary.md) the peer will authenticate, per [`RUN-PROVISION-001`](provisioning.md).
- The MME's expected HSS Origin-Host and the operator's Diameter realm are known, so `origin_host` and `origin_realm` can be set to match (see the [S6a Diameter configuration reference](../configuration/diameter.md) §5.1–§5.2).
- The address on which the MME will reach the HSS is routable from the MME, and the S6a port (standard `3868`) is permitted by any intervening firewall.
- An external Diameter peer (MME or test client) is available to originate the CER and the AIR.

### Inputs and privileges

- The routable IPv4 address and port to bind, as an Erlang tuple, for example `{tcp, {10,0,0,5}, 3868}`.
- The HSS `origin_host` and `origin_realm` values the MME expects.
- Permission to edit `config/sys.config` and to restart the node.

> [!WARNING]
> The shipped `listen` value `[{tcp, {127,0,0,1}, 3868}]` binds the S6a listener to loopback only, so no external MME can connect. To accept an external MME, `listen` `shall` include an entry bound to a routable address, and an entry bound to `{127,0,0,1}` `shall not` be the only entry (see the [S6a Diameter configuration reference](../configuration/diameter.md) §5.3).

### Steps

1. Set the S6a identity and listener in `config/sys.config` under `udr_diameter` to match the peer and to bind a routable address:

   ```erlang
   {udr_diameter, [
     {origin_host, "hss01.epc.mnc001.mcc001.3gppnetwork.org"},
     {origin_realm, "epc.mnc001.mcc001.3gppnetwork.org"},
     {listen, [{tcp, {10,0,0,5}, 3868}]}
   ]}
   ```

2. Restart the node so the change takes effect, per [`RUN-LIFECYCLE-001`](lifecycle.md). (With the ETS backend, re-provision the test subscriber after the restart, because ETS data does not survive a restart; see [`RUN-PROVISION-001`](provisioning.md).)
3. On the MME (or test client), configure its HSS peer to the HSS's routable address and port, its expected HSS Origin-Host to the `origin_host` set in Step 1, and its realm to `origin_realm`. The peer-side configuration is out of scope here.
4. Bring up the peer so it establishes the Diameter connection and sends its CER.

### Verify

*(Observable outcome.)*

- Confirm the listener is bound on the configured routable address:

  ```sh
  ss -ltn '( sport = :3868 )'
  ```

  A socket `shall` be listed on the address set in `listen` (here `10.0.0.5`).

- Confirm the capability exchange: the peer's CER `shall` be answered with a CEA carrying the configured `origin_host` in its Origin-Host AVP. Observe this on the peer's Diameter state (it `shall` report the HSS peer as open/connected) or on a packet capture of the S6a port.

- Confirm an AIR is served: drive an AIR for the provisioned IMSI from the peer. The HSS `shall` answer with an AIA carrying `Result-Code` `2001` and an `Authentication-Info` AVP containing at least one `E-UTRAN-Vector` (see the [S6a interface reference](../interfaces/s6a.md) §5.1, §8). When a trace exporter is configured, the AIR produces an `s6a.AIR` [OpenTelemetry](../glossary.md) span with attribute `s6a.result` = `success` (see [`RUN-OBSERVABILITY-001`](observability.md)).

### Rollback / on failure

- If no socket is listed on the routable address, the `listen` change did not take effect or the node did not restart; re-check `config/sys.config` and restart, per [`RUN-LIFECYCLE-001`](lifecycle.md).
- If the peer's CER is not answered or the peer rejects the CEA, confirm the peer can reach the bound address and port, and that the peer's expected HSS Origin-Host matches `origin_host`; a mismatch can cause the peer to reject the connection (see the [S6a Diameter configuration reference](../configuration/diameter.md) §5.1).
- If an AIR returns an Experimental-Result `5001` (user unknown) rather than vectors, the IMSI is not provisioned on this node; provision it per [`RUN-PROVISION-001`](provisioning.md) (recall that an ETS-backed node loses provisioning across a restart). Result codes are listed in the [S6a interface reference](../interfaces/s6a.md) §7.
- To return to the safe default, restore `listen` to `[{tcp, {127,0,0,1}, 3868}]` and restart; the listener then binds loopback only and no external peer can connect.

### Related

- [S6a interface reference](../interfaces/s6a.md) — AIR/ULR/PUR/CLR contract and result codes.
- [S6a Diameter configuration reference](../configuration/diameter.md) — `origin_host`, `origin_realm`, `listen`.
- [`RUN-PROVISION-001`](provisioning.md) — provision the subscriber the AIR authenticates.
- [`RUN-OBSERVABILITY-001`](observability.md) — see the `s6a.AIR` span the AIR produces.
