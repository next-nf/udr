%% SPDX-License-Identifier: AGPL-3.0-or-later
%%
%% Copyright (C) 2026 Nathan Foster <next-nf@proton.me>
%%
%% This program is free software: you can redistribute it and/or modify it under
%% the terms of the GNU Affero General Public License as published by the Free
%% Software Foundation, either version 3 of the License, or (at your option) any
%% later version. See <https://www.gnu.org/licenses/>.
%%
%% A minimal S6a Diameter MME client for the s6a-smoke demo. It connects to the
%% HSS over TCP, sends an AIR and a ULR, and asserts the answers (AIA with the
%% requested number of vectors, ULA with Result-Code 2001). Exits 0 on success,
%% non-zero on any failure. Adapted from apps/udr_diameter/test/udr_diameter_test_mme.erl.
-module(smoke_mme).
-moduledoc false.
-behaviour(diameter_app).
-include_lib("diameter/include/diameter.hrl").

-export([main/0]).
-export([peer_up/3, peer_down/3, pick_peer/4, prepare_request/3,
         prepare_retransmit/3, handle_answer/4, handle_error/4, handle_request/3]).

-define(SVC, smoke_mme).
-define(OWN_HOST, <<"mme-a">>).
-define(OWN_REALM, <<"epc">>).
%% Destination-Realm must match the HSS origin_realm (config/docker.sys.config)
%% so diameter routes the request to the HSS peer.
-define(HSS_REALM, <<"epc.mnc001.mcc001.3gppnetwork.org">>).
-define(APP_ID, 16777251).
-define(VENDOR_3GPP, 10415).
-define(VISITED_PLMN, <<0, 16#f1, 16#10>>).

%% --- entry point (invoked via `erl -run smoke_mme main`) ---

-spec main() -> no_return().
main() ->
    Host = getenv("HSS_HOST", "hss"),
    Port = list_to_integer(getenv("HSS_PORT", "3868")),
    Imsi = list_to_binary(getenv("IMSI", "001010000000001")),
    N    = list_to_integer(getenv("NUM_VECTORS", "2")),
    io:format("S6a smoke client -> ~s:~p  (IMSI ~s, ~p vectors)~n", [Host, Port, Imsi, N]),
    try run(Host, Port, Imsi, N) of
        ok -> io:format("RESULT: PASS~n"), halt(0)
    catch
        throw:{fail, Why} ->
            io:format("RESULT: FAIL -- ~p~n", [Why]), halt(1);
        Class:Reason:Stack ->
            io:format("RESULT: ERROR -- ~p:~p~n~p~n", [Class, Reason, Stack]), halt(2)
    end.

run(Host, Port, Imsi, N) ->
    {ok, Addr} = inet:getaddr(Host, inet),
    {ok, _} = start(Addr, Port),
    %% AIR -> AIA carrying N E-UTRAN vectors
    case air(Imsi, N) of
        {ok, ['AIA' | A]} ->
            assert_rc('AIA', A),
            Vs = case maps:get('Authentication-Info', A, []) of
                     [#{'E-UTRAN-Vector' := EVs}] -> EVs;
                     _ -> []
                 end,
            (length(Vs) =:= N)
                orelse throw({fail, {air_vector_count, length(Vs), expected, N}}),
            io:format("  AIR -> AIA  Result-Code=2001  vectors=~p  OK~n", [length(Vs)]);
        AirOther ->
            throw({fail, {air, AirOther}})
    end,
    %% ULR -> ULA registering the serving MME
    case ulr(Imsi, ?OWN_HOST) of
        {ok, ['ULA' | U]} ->
            assert_rc('ULA', U),
            io:format("  ULR -> ULA  Result-Code=2001  OK~n");
        UlrOther ->
            throw({fail, {ulr, UlrOther}})
    end,
    _ = stop(),
    ok.

assert_rc(Tag, Avps) ->
    case maps:get('Result-Code', Avps, undefined) of
        [2001] -> ok;
        RC ->
            throw({fail, {Tag, result_code, RC,
                          experimental, maps:get('Experimental-Result', Avps, undefined)}})
    end.

getenv(Key, Default) ->
    case os:getenv(Key) of
        false -> Default;
        ""    -> Default;
        Value -> Value
    end.

%% --- diameter lifecycle ---

start(Addr, Port) ->
    {ok, _} = application:ensure_all_started(diameter),
    ok = diameter:start_service(?SVC, svc_opts()),
    {ok, _Ref} = diameter:add_transport(?SVC, {connect, connect_opts(Addr, Port)}),
    ok = wait_up(100),
    {ok, self()}.

stop() ->
    _ = diameter:stop_service(?SVC),
    ok.

svc_opts() ->
    [{'Origin-Host', ?OWN_HOST},
     {'Origin-Realm', ?OWN_REALM},
     {'Vendor-Id', ?VENDOR_3GPP},
     {'Product-Name', "udr-s6a-smoke"},
     {'Auth-Application-Id', [?APP_ID]},
     {'Vendor-Specific-Application-Id',
        [[{'Vendor-Id', ?VENDOR_3GPP}, {'Auth-Application-Id', [?APP_ID]}]]},
     {string_decode, false},
     {decode_format, map},
     {application, [{alias, s6a},
                    {dictionary, diameter_3gpp_s6a},
                    {module, ?MODULE}]}].

connect_opts(Addr, Port) ->
    [{transport_module, diameter_tcp},
     {transport_config, [{raddr, Addr}, {rport, Port}, {reuseaddr, true}]}].

%% Poll until the transport to the HSS is up (CER/CEA complete), ~10 s max.
wait_up(0) ->
    throw({fail, no_connection_to_hss});
wait_up(N) ->
    case diameter:service_info(?SVC, connections) of
        [_ | _] -> ok;
        _       -> timer:sleep(100), wait_up(N - 1)
    end.

%% --- requests ---

air(Imsi, N) ->
    Avps = (common(?OWN_HOST))#{
        'User-Name' => Imsi,
        'Visited-PLMN-Id' => ?VISITED_PLMN,
        'Requested-EUTRAN-Authentication-Info' =>
            [#{'Number-Of-Requested-Vectors' => [N]}]},
    diameter:call(?SVC, s6a, ['AIR' | Avps], []).

ulr(Imsi, MmeHost) ->
    Avps = (common(MmeHost))#{
        'User-Name' => Imsi,
        'RAT-Type' => 1004,        %% EUTRAN
        'ULR-Flags' => 0,
        'Visited-PLMN-Id' => ?VISITED_PLMN},
    diameter:call(?SVC, s6a, ['ULR' | Avps], []).

common(OriginHost) ->
    #{'Session-Id' => list_to_binary(diameter:session_id(binary_to_list(?OWN_HOST))),
      'Auth-Session-State' => 1,    %% NO_STATE_MAINTAINED
      'Origin-Host' => OriginHost,
      'Origin-Realm' => ?OWN_REALM,
      'Destination-Realm' => ?HSS_REALM}.

%% --- diameter_app callbacks ---

peer_up(_Svc, _Peer, State)   -> State.
peer_down(_Svc, _Peer, State) -> State.

pick_peer([Peer | _], _, _Svc, _St) -> {ok, Peer};
pick_peer([], _, _Svc, _St)         -> false.

prepare_request(Pkt, _Svc, _Peer)    -> {send, Pkt}.
prepare_retransmit(Pkt, _Svc, _Peer) -> {send, Pkt}.

handle_answer(#diameter_packet{msg = Msg}, _Req, _Svc, _Peer) -> {ok, Msg}.
handle_error(Reason, _Req, _Svc, _Peer)                       -> {error, Reason}.

%% The HSS does not send requests to the client in this demo; ignore any.
handle_request(_Pkt, _Svc, _Peer) -> discard.
