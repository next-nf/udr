# Operations Runbook: Cluster Formation

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers forming a cluster of `udr` nodes, adding a node to a running cluster, and removing one. A cluster shares the cluster-wide per-[IMSI](../glossary.md) session lock space, provided by `udr_cluster` over [`syn`](../glossary.md), so that concurrent signaling for one subscriber serializes across nodes. It is for operators scaling the HSS beyond one node. The clustering prerequisites and the per-IMSI locking behavior are described in the [cluster configuration reference](../configuration/cluster.md); the node name and cookie are defined in the [node reference](../configuration/node.md).

> [!NOTE]
> A single node forms a cluster of one and needs no distribution configuration. Clustering is established entirely by Erlang distribution — a distinct node name and a shared cookie — and `udr_cluster` joins each node to the `udr_session` [`syn`](../glossary.md) scope at start. There is no `udr_cluster` key to enable or size clustering (see the [cluster configuration reference](../configuration/cluster.md) §4).

---

## RUN-CLUSTER-001: Form a cluster, add a node, and remove a node

### Purpose

*(Informative.)* This procedure interconnects two or more nodes into one Erlang distribution mesh so they share the per-IMSI lock space, adds a further node to a running mesh, and removes a node cleanly. An operator runs it to scale out the HSS and to take a node out of service.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- Each node is deployed and runnable, per [`RUN-DEPLOY-001`](deploy.md), and each is started per [`RUN-LIFECYCLE-001`](lifecycle.md).
- Each node `shall` run with a distinct node name. For nodes on different hosts, `-name` with a fully-qualified `name@fqdn` `shall` be used in `config/vm.args`, because short names do not interconnect across hosts (see the [node reference](../configuration/node.md) §5.1).
- Every node `shall` carry the same `-setcookie` value; a cookie mismatch prevents interconnection and therefore prevents lock sharing (see the [node reference](../configuration/node.md) §5.2).
- The Erlang distribution port and the [`epmd`](../glossary.md) port (TCP `4369`) `shall` be reachable between the nodes.

### Inputs and privileges

- The node names and the shared cookie for all members.
- Permission to edit `config/vm.args` and to restart each node.
- Network reach between members on the distribution and `epmd` ports.

> [!CAUTION]
> The distribution cookie is a security boundary. A host that knows the cookie and can reach the distribution port can run code on every node in the mesh. The shipped `udr_cookie` `shall` be replaced with a unique secret value, and the distribution and `epmd` ports `shall` be restricted to a trusted network, before clustering across hosts (see the [node reference](../configuration/node.md) §5.2).

> [!WARNING]
> While nodes are not interconnected (for example because of a cookie mismatch or an unreachable distribution port), each node holds locks only locally, and two nodes can process signaling for the same IMSI concurrently. Confirm interconnection (see Verify) before relying on cluster-wide serialization.

### Steps

1. **Configure each node for distribution.** In each node's `config/vm.args`, set a distinct `-name` (FQDN form for multi-host) and the shared `-setcookie`. For two nodes:

   ```text
   # node 1
   -name udr1@hss1.epc.example.net
   -setcookie s3cr3t-shared-cookie
   ```

   ```text
   # node 2
   -name udr2@hss2.epc.example.net
   -setcookie s3cr3t-shared-cookie
   ```

2. Start each node, per [`RUN-LIFECYCLE-001`](lifecycle.md).
3. **Interconnect the nodes.** From one node's console, connect to each other member:

   ```erlang
   net_adm:ping('udr2@hss2.epc.example.net').
   ```

   Erlang distribution is transitive: once a node joins the mesh, the existing members learn of it. `udr_cluster_app` has already joined each node to the `udr_session` scope at start, so a node that joins the mesh shares the lock space without further action.
4. **Add a node to a running cluster.** Configure the new node (Step 1) with the same cookie and a distinct name, start it (Step 2), then from the new node ping any existing member (Step 3). The new node joins the mesh and the shared scope.
5. **Remove a node.** Stop the node to be removed, per [`RUN-LIFECYCLE-001`](lifecycle.md); on `stop` it leaves the distribution mesh and the `syn` scope. The remaining nodes continue to share the lock space among themselves.

### Verify

*(Observable outcome.)*

- Confirm interconnection. From node 1's console (see [`RUN-LIFECYCLE-001`](lifecycle.md)):

  ```erlang
  nodes().
  ```

  The result `shall` list every peer, for example `['udr2@hss2.epc.example.net']`. A `net_adm:ping/1` of a peer `shall` return `pong` (a cookie mismatch or unreachable peer returns `pang`).

- Confirm the session scope is active on each node:

  ```erlang
  udr_cluster:scope().
  ```

  The result `shall` be the atom `udr_session`.

- Confirm cluster-wide locking. Hold a lock for an IMSI on node 1 (inside a long-running `udr_cluster:with_session/2` call), then on node 2 query the holder:

  ```erlang
  udr_cluster:whereis_session(<<"001010000000001">>).
  ```

  The result `shall` be the pid on node 1, showing both nodes see the same lock owner.

- After removing a node (Step 5), `nodes()` on a remaining node `shall not` list the removed node.

### Rollback / on failure

- If `net_adm:ping/1` returns `pang`, the nodes did not interconnect. Confirm the cookies match (`erlang:get_cookie()` on each), the node names are distinct and resolvable, and that the distribution and `epmd` ports are reachable (`epmd -names` lists each node). Correct and re-ping.
- If `nodes()` is empty after a ping that returned `pong`, re-check that both nodes use FQDN `-name` values across hosts (short names do not interconnect across hosts; see the [node reference](../configuration/node.md) §5.1).
- To dissolve the cluster, stop the added nodes (Step 5); the remaining node returns to a cluster of one and continues to hold locks locally.

### Related

- [Cluster configuration reference](../configuration/cluster.md) — per-IMSI locking and the clustering prerequisites.
- [Node and release configuration reference](../configuration/node.md) — node name and cookie.
- [`RUN-LIFECYCLE-001`](lifecycle.md) — start and stop the nodes that form the cluster.
