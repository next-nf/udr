%% SPDX-License-Identifier: AGPL-3.0-or-later
%%
%% Copyright (C) 2026 Nathan Foster <next-nf@proton.me>
%%
%% This program is free software: you can redistribute it and/or modify
%% it under the terms of the GNU Affero General Public License as
%% published by the Free Software Foundation, either version 3 of the
%% License, or (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU Affero General Public License for more details.
%%
%% You should have received a copy of the GNU Affero General Public License
%% along with this program.  If not, see <https://www.gnu.org/licenses/>.
-module(udr_hss_dist_SUITE).
-moduledoc """
Multi-node + MongoDB integration of the HSS+UDR stack.

This is the distributed cousin of `udr_hss_integration_SUITE`: instead of one
node with the ETS backend, it brings up TWO real Erlang worker nodes that both
run the full `udr_hss` stack against ONE shared MongoDB, and drives them from
the (coordinator-only) Common Test node via `erpc`. It proves the three things a
single node cannot: shared state through Mongo, the version-CAS in the Mongo
backend serialising writes across nodes, and the `syn` per-IMSI session lock
spanning nodes.

## `?CT_PEER` notes (the tricky bits)

  * The origin (the CT node) must already be a *distributed* node, because
    `?CT_PEER` controls the peers over the Erlang distribution channel
    (`peer:start_link` errors with `not_alive` otherwise). We do NOT start
    distribution from inside the suite -- run CT distributed instead, e.g.
    `rebar3 ct --sname test`. When the origin is not alive the suite skips
    cleanly; it never fails the run.
  * Each peer boots with the origin's full code path baked into its startup
    args (`args => ["-pa" | code:get_path()]`), so `syn`/`mongodb`/`udr_*` are
    loadable before any app starts -- no post-boot `code:add_paths/1` round trip.
  * `wait_boot => 20000`: a peer boot on a cold/loaded CI runner can exceed the
    15s `peer` default, and a boot timeout *exits the starter* (it is not a
    clean skip and trips the CT exit code), so we give it generous headroom.
  * `?CT_PEER` (`peer:start_link`) links the peer's control process to the
    *caller*. In `init_per_suite` that caller is short-lived, so we `unlink/1`
    the peer to keep it alive for the whole suite and stop it in `end_per_suite`.
  * Default `connect_all` meshes the two peers, so the `syn` `udr_session` scope
    spans both worker nodes.

The suite is skipped (not failed) when the origin is not distributed or when
podman/mongo:7 is unavailable.
""".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("udr_hss_test.hrl").

-export([all/0, suite/0, init_per_suite/1, end_per_suite/1]).
-export([lifecycle_across_nodes/1, cross_node_sqn_serialization/1,
         cross_node_session_lock/1]).
%% Invoked ON a worker node via MFA (erpc / spawn/4) -- exported so no fun is
%% ever shipped across nodes (a shipped closure couples the peer to this module's
%% exact loaded version, which is the kind of fragility that makes peer tests flaky).
-export([configure_backend/1, hammer_advance/3,
         hold_session/2, try_lock/2, spawn_idle/0]).

-define(CONTAINER, "udr-mongo-dist").
-define(PORT, 27018).                       %% distinct from the conformance suite's 27017
-define(DB, <<"udr_dist">>).

%% Real MILENAGE test vector (same as udr_hss_integration_SUITE).
-define(KI_HEX,  <<"465b5ce8b199b49faa5f0a2ee238a6bc">>).
-define(OPC_HEX, <<"cd63cb71954a9f4e48a5994e37a02baf">>).
-define(AMF_HEX, <<"b9b9">>).

all() ->
    [lifecycle_across_nodes, cross_node_sqn_serialization, cross_node_session_lock].

%% Generous: a first-ever mongo:7 boot plus two peer-node boots.
suite() -> [{timetrap, {minutes, 5}}].

%% --- suite fixture: distribution, mongo, two worker nodes -----------------

init_per_suite(Config) ->
    case erlang:is_alive() of
        false ->
            {skip, "CT node is not distributed -- run with `rebar3 ct --sname test`"};
        true ->
            case udr_mongo_ct:start(?CONTAINER, ?PORT) of
                {skip, Reason} ->
                    {skip, Reason};
                {ok, #{host := Host, port := Port}} ->
                    Opts = #{database => ?DB, host => Host, port => Port},
                    {NodeA, PeerA} = start_worker(Opts),
                    {NodeB, PeerB} = start_worker(Opts),
                    ok = await_cluster(NodeA, NodeB),
                    [{peers, [PeerA, PeerB]},
                     {node_a, NodeA}, {node_b, NodeB} | Config]
            end
    end.

end_per_suite(Config) ->
    [ catch peer:stop(P) || P <- proplists:get_value(peers, Config, []) ],
    udr_mongo_ct:stop(?CONTAINER),
    ok.

%% --- testcases ------------------------------------------------------------

%% The full attach lifecycle, with each S6a step executed on a DIFFERENT node,
%% so every assertion depends on state another node wrote to the shared Mongo:
%% provision on A -> AIR on B -> ULR(mme-a) on A -> ULR(mme-b) on B (which must
%% see A's registration and emit a CLR for mme-a) -> PUR on A -> B sees it purged.
lifecycle_across_nodes(Config) ->
    A = ?config(node_a, Config),
    B = ?config(node_b, Config),
    Imsi = <<"001010000000201">>,
    Plmn = ?VISITED_PLMN_001_01,

    ok = erpc:call(A, udr_data, put_authentication_subscription,
                   [Imsi, #{<<"ki">>        => binary:decode_hex(?KI_HEX),
                            <<"opc">>       => binary:decode_hex(?OPC_HEX),
                            <<"algorithm">> => <<"milenage">>,
                            <<"amf">>       => binary:decode_hex(?AMF_HEX),
                            <<"sqn">>       => 0}]),
    ok = erpc:call(A, udr_data, put_subscription_data,
                   [Imsi, #{<<"msisdn">> => <<"49170">>,
                            <<"apn_config_profile">> => #{<<"context_id">> => 1}}]),

    {ok, #{vectors := Vs}, []} =
        erpc:call(B, udr_hss, handle_air,
                  [#{imsi => Imsi, visited_plmn => Plmn, num_vectors => 3}]),
    ?assertEqual(3, length(Vs)),

    U1 = #{imsi => Imsi, mme_host => <<"mme-a">>, mme_realm => <<"epc">>,
           rat_type => eutran, visited_plmn => Plmn},
    {ok, #{subscription_data := _}, []} = erpc:call(A, udr_hss, handle_ulr, [U1]),

    U2 = U1#{mme_host => <<"mme-b">>},
    {ok, _, [{cancel_location, #{mme_host := <<"mme-a">>}}]} =
        erpc:call(B, udr_hss, handle_ulr, [U2]),

    {ok, #{freeze_m_tmsi := true}, []} =
        erpc:call(A, udr_hss, handle_pur, [#{imsi => Imsi, mme_host => <<"mme-b">>}]),
    {ok, PReg} = erpc:call(B, udr_data, get_3gpp_access_registration, [Imsi]),
    ?assertEqual(true, maps:get(<<"ue_purged">>, PReg)),
    ok.

%% Both nodes hammer advance_sqn/2 on the SAME subscriber concurrently. Each
%% reservation is a version-CAS against the one Mongo document, so correctness
%% requires the backend's optimistic concurrency to serialise writes ACROSS
%% nodes: every reserved start SQN must be unique and the block must be gapless
%% (0..Total-1), with the final stored SQN equal to Total.
cross_node_sqn_serialization(Config) ->
    A = ?config(node_a, Config),
    B = ?config(node_b, Config),
    Imsi = <<"001010000000202">>,
    Workers = 5,
    PerWorker = 6,
    Total = 2 * Workers * PerWorker,

    ok = erpc:call(A, udr_data, put_authentication_subscription, [Imsi, #{<<"sqn">> => 0}]),

    [{ok, StartsA}, {ok, StartsB}] =
        erpc:multicall([A, B], ?MODULE, hammer_advance, [Imsi, Workers, PerWorker]),
    AllStarts = StartsA ++ StartsB,

    ?assertEqual(Total, length(AllStarts)),
    ?assertEqual(lists:seq(0, Total - 1), lists:sort(AllStarts)),
    {ok, #{<<"sqn">> := Final}} =
        erpc:call(A, udr_data, get_authentication_subscription, [Imsi]),
    ?assertEqual(Total, Final),
    ok.

%% The per-IMSI session lock is cluster-wide: a session held on node A blocks
%% acquisition on node B, and frees it on release. (syn over distribution, but
%% exercised through the same mongo-backed stack the handlers run in.)
cross_node_session_lock(Config) ->
    A = ?config(node_a, Config),
    B = ?config(node_b, Config),
    Imsi = <<"001010000000203">>,
    Ctl = self(),

    %% spawn/4 ships an MFA, not a fun: hold_session runs on A and builds its
    %% (local) critical-section fun there.
    Holder = erlang:spawn(A, ?MODULE, hold_session, [Imsi, Ctl]),
    receive {held, Holder} -> ok
    after 5000 -> ct:fail(lock_not_acquired_on_a) end,

    %% The {held,_} signal only proves A registered LOCALLY. syn is eventually
    %% consistent across nodes, so wait until B actually resolves A's holder
    %% before asserting busy -- otherwise B can race ahead of propagation, see
    %% no holder, and acquire (the intermittent failure this test first had).
    wait_until(fun() ->
        Holder =:= erpc:call(B, udr_cluster, whereis_session, [Imsi])
    end, 100),

    ?assertEqual({error, session_busy}, erpc:call(B, ?MODULE, try_lock, [Imsi, 200])),

    Holder ! release,
    wait_until(fun() -> ok =:= erpc:call(B, ?MODULE, try_lock, [Imsi, 500]) end, 50),
    ok.

%% --- worker node lifecycle ------------------------------------------------

%% Start one peer worker node (full code path baked into its boot args), point
%% it at the shared Mongo (Opts), and bring up the udr_hss stack on it.
start_worker(Opts) ->
    {ok, Peer, Node} = ?CT_PEER(#{name => ?CT_PEER_NAME(),
                                  args => ["-pa" | code:get_path()],
                                  wait_boot => 20000}),
    unlink(Peer),
    ok = erpc:call(Node, ?MODULE, configure_backend, [Opts]),
    {ok, _Started} = erpc:call(Node, application, ensure_all_started, [udr_hss]),
    {Node, Peer}.

%% Runs ON a worker node: select the Mongo backend before udr_db starts. Load
%% udr_db first so the env override is not reset to the .app default when
%% ensure_all_started loads the app.
configure_backend(Opts) ->
    _ = application:load(udr_db),
    ok = application:set_env(udr_db, backend, udr_db_mongo),
    ok = application:set_env(udr_db, backend_opts, Opts),
    _ = persistent_term:erase({udr_db, backend}),
    ok.

%% Runs ON a worker node: NWorkers processes each reserve PerWorker single SQNs;
%% returns the flat list of reserved start values.
hammer_advance(Imsi, NWorkers, PerWorker) ->
    Parent = self(),
    Pids = [ erlang:spawn_link(fun() ->
                 Starts = [ begin {ok, S} = udr_data:advance_sqn(Imsi, 1), S end
                            || _ <- lists:seq(1, PerWorker) ],
                 Parent ! {self(), Starts}
             end) || _ <- lists:seq(1, NWorkers) ],
    lists:append([ receive {P, Ss} -> Ss end || P <- Pids ]).

%% Runs ON a worker node: hold the per-IMSI session, tell the controller it is
%% held (tagged with this holder's pid), and release only when told to.
hold_session(Imsi, Ctl) ->
    udr_cluster:with_session(Imsi, fun() ->
        Ctl ! {held, self()},
        receive release -> ok end
    end).

%% Runs ON a worker node: try to enter the session within Timeout ms.
try_lock(Imsi, Timeout) ->
    udr_cluster:with_session(Imsi, fun() -> ok end, Timeout).

%% Runs ON a worker node: an idle process used as a syn sync sentinel.
spawn_idle() ->
    erlang:spawn(fun() -> receive stop -> ok end end).

%% Block until the syn udr_session scope is synced BOTH ways across the worker
%% nodes -- each must resolve a holder the other registered -- so the cross-node
%% lock test is not racing scope formation (which matters when an earlier suite
%% left the CT node in the scope, making this a 3-node merge).
await_cluster(NodeA, NodeB) ->
    ok = await_visible(NodeA, NodeB, <<"cluster-sync-ab">>),
    ok = await_visible(NodeB, NodeA, <<"cluster-sync-ba">>),
    ok.

await_visible(Observer, Registrar, Imsi) ->
    Scope = udr_cluster:scope(),
    Holder = erpc:call(Registrar, ?MODULE, spawn_idle, []),
    ok = erpc:call(Registrar, syn, register, [Scope, Imsi, Holder]),
    Res = wait_until(fun() ->
              Holder =:= erpc:call(Observer, udr_cluster, whereis_session, [Imsi])
          end, 200),
    _ = erpc:call(Registrar, syn, unregister, [Scope, Imsi]),
    exit(Holder, kill),
    Res.

wait_until(_F, 0) -> erlang:error(timeout);
wait_until(F, N) ->
    case F() of
        true  -> ok;
        false -> timer:sleep(50), wait_until(F, N - 1)
    end.
