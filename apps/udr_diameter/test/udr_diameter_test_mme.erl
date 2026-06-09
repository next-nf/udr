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
-module(udr_diameter_test_mme).
-moduledoc false.
-behaviour(diameter_app).
-include_lib("diameter/include/diameter.hrl").

-export([start/1, stop/0, air/2, bad_air/1, ulr/2, pur/1, received_clr/2, recorded_clr/1]).
-export([peer_up/3, peer_down/3, pick_peer/4, prepare_request/3,
         prepare_retransmit/3, handle_answer/4, handle_error/4, handle_request/3]).

-define(SVC, test_mme).
-define(OWN_HOST, <<"mme-a">>).
-define(OWN_REALM, <<"epc">>).
%% The HSS realm (udr_diameter app.src default origin_realm); requests must carry
%% a Destination-Realm matching it so diameter selects the HSS peer.
-define(HSS_REALM, <<"epc.mnc001.mcc001.3gppnetwork.org">>).
-define(APP_ID, 16777251).
-define(VENDOR_3GPP, 10415).
-define(VISITED_PLMN, <<0, 16#f1, 16#10>>).

%% --- lifecycle ---

-spec start(inet:port_number()) -> {ok, pid()} | {error, term()}.
start(Port) ->
    {ok, _} = application:ensure_all_started(diameter),
    ok = diameter:start_service(?SVC, svc_opts()),
    {ok, _Ref} = diameter:add_transport(?SVC, {connect, connect_opts(Port)}),
    ok = wait_up(50),
    {ok, self()}.

-spec stop() -> ok.
stop() ->
    _ = diameter:stop_service(?SVC),
    ok.

svc_opts() ->
    [{'Origin-Host', ?OWN_HOST},
     {'Origin-Realm', ?OWN_REALM},
     {'Vendor-Id', ?VENDOR_3GPP},
     {'Product-Name', "test-mme"},
     {'Auth-Application-Id', [?APP_ID]},
     {'Vendor-Specific-Application-Id',
        [[{'Vendor-Id', ?VENDOR_3GPP}, {'Auth-Application-Id', [?APP_ID]}]]},
     {string_decode, false},
     {decode_format, map},
     {application, [{alias, s6a},
                    {dictionary, diameter_3gpp_s6a},
                    {module, ?MODULE},
                    %% Deliver answers to handle_answer/4 even when they decode
                    %% with errors. The HSS's error answer-message (a bare 318
                    %% answer carrying Result-Code, built in the common dict)
                    %% lacks AIA-mandatory AVPs, so it decodes with errors here;
                    %% without this it would be handled internally and bad_air/1
                    %% could not observe the Result-Code.
                    {answer_errors, callback}]}].

connect_opts(Port) ->
    [{transport_module, diameter_tcp},
     {transport_config, [{raddr, {127, 0, 0, 1}},
                         {rport, Port},
                         {reuseaddr, true}]}].

%% Poll until the transport to the HSS is up (CER/CEA complete).
wait_up(0) ->
    {error, no_connection};
wait_up(N) ->
    case diameter:service_info(?SVC, connections) of
        [_ | _] -> ok;
        _       -> timer:sleep(100), wait_up(N - 1)
    end.

%% --- requests (synchronous: return {ok, [Name | Map]} | {error, term()}) ---

-spec air(binary(), pos_integer()) -> {ok, list()} | {error, term()}.
air(Imsi, N) ->
    Avps = (common(?OWN_HOST))#{
        'User-Name' => Imsi,
        'Visited-PLMN-Id' => ?VISITED_PLMN,
        'Requested-EUTRAN-Authentication-Info' =>
            [#{'Number-Of-Requested-Vectors' => [N]}]},
    diameter:call(?SVC, s6a, ['AIR' | Avps], []).

%% Send an AIR that decodes with errors on the HSS: a well-formed AIR plus one
%% extra unknown AVP with the Mandatory (M) bit set. The HSS dictionary has no
%% catch-all `* [ AVP ]` in AIR, so the decode reports the unknown mandatory AVP
%% in #diameter_packet.errors. The HSS service answers this itself (configured
%% {request_errors, answer}); this is the real-traffic path that crashed the HSS
%% request process before the RFC 6733 common application was registered (see
%% udr_diameter_srv).
-spec bad_air(binary()) -> {ok, list()} | {error, term()}.
bad_air(Imsi) ->
    Unknown = #diameter_avp{code = 16#00FFFFFE, is_mandatory = true,
                            data = <<0, 0, 0, 0>>},
    Avps = (common(?OWN_HOST))#{
        'User-Name' => Imsi,
        'Visited-PLMN-Id' => ?VISITED_PLMN,
        'Requested-EUTRAN-Authentication-Info' =>
            [#{'Number-Of-Requested-Vectors' => [1]}],
        'AVP' => [Unknown]},
    diameter:call(?SVC, s6a, ['AIR' | Avps], []).

-spec ulr(binary(), binary()) -> {ok, list()} | {error, term()}.
ulr(Imsi, MmeHost) ->
    Avps = (common(MmeHost))#{
        'User-Name' => Imsi,
        'RAT-Type' => 1004,        %% EUTRAN
        'ULR-Flags' => 0,
        'Visited-PLMN-Id' => ?VISITED_PLMN},
    diameter:call(?SVC, s6a, ['ULR' | Avps], []).

-spec pur(binary()) -> {ok, list()} | {error, term()}.
pur(Imsi) ->
    Avps = (common(?OWN_HOST))#{'User-Name' => Imsi},
    diameter:call(?SVC, s6a, ['PUR' | Avps], []).

%% Common request AVPs. OriginHost is the serving-MME identity the HSS records;
%% it is carried in the message even though the connection identity stays mme-a.
common(OriginHost) ->
    #{'Session-Id' => list_to_binary(diameter:session_id(binary_to_list(?OWN_HOST))),
      'Auth-Session-State' => 1,    %% NO_STATE_MAINTAINED
      'Origin-Host' => OriginHost,
      'Origin-Realm' => ?OWN_REALM,
      'Destination-Realm' => ?HSS_REALM}.

%% --- recorded-CLR store ---
%% persistent_term keeps recorded CLRs independent of any process lifetime: the
%% diameter callback process records them and the CT case process reads them.

-spec received_clr(binary(), non_neg_integer()) -> boolean().
received_clr(Imsi, Timeout) ->
    case persistent_term:get({?MODULE, clr, Imsi}, undefined) of
        undefined when Timeout =< 0 -> false;
        undefined -> timer:sleep(50), received_clr(Imsi, Timeout - 50);
        _Avps     -> true
    end.

%% Return the AVP map of the last CLR recorded for an IMSI (undefined if none).
-spec recorded_clr(binary()) -> map() | undefined.
recorded_clr(Imsi) ->
    persistent_term:get({?MODULE, clr, Imsi}, undefined).

%% --- diameter_app callbacks ---

peer_up(_Svc, _Peer, State)   -> State.
peer_down(_Svc, _Peer, State) -> State.

pick_peer([Peer | _], _, _Svc, _St) -> {ok, Peer};
pick_peer([], _, _Svc, _St)         -> false.

%% Malformed-AIR path (bad_air/1): the message carries an 'AVP' field holding raw
%% #diameter_avp{} records that the strict encoder would otherwise drop (AIR has
%% no `* [ AVP ]` slot). Encode the clean AIR ourselves, splice each extra AVP
%% onto the wire, and fix the 24-bit Message Length. diameter sends a packet whose
%% #diameter_packet.bin is already set verbatim (diameter_traffic:encode/4), so
%% the HSS receives bytes its grammar rejects and decodes them with errors.
prepare_request(#diameter_packet{msg = ['AIR' | #{'AVP' := Extras} = Map]} = Pkt,
                _Svc, _Peer) ->
    Clean = Pkt#diameter_packet{msg = ['AIR' | maps:remove('AVP', Map)]},
    #diameter_packet{bin = Bin} =
        diameter_codec:encode(diameter_3gpp_s6a,
                              #{ordered_encode => true, string_decode => false},
                              Clean),
    Extra = iolist_to_binary([avp_to_wire(A) || A <- Extras]),
    <<V:8, Len:24, Rest/binary>> = Bin,
    Bad = <<V:8, (Len + byte_size(Extra)):24, Rest/binary, Extra/binary>>,
    {send, Pkt#diameter_packet{bin = Bad}};
prepare_request(Pkt, _Svc, _Peer)    -> {send, Pkt}.
prepare_retransmit(Pkt, _Svc, _Peer) -> {send, Pkt}.

%% Encode one raw AVP to wire form (RFC 6733 6: Code|Flags|Length|Data|pad), no
%% vendor id. Only the M flag is honoured -- enough to force a decode error.
avp_to_wire(#diameter_avp{code = Code, is_mandatory = M, data = Data}) ->
    Flags = case M of true -> 16#40; false -> 0 end,
    Len = 8 + byte_size(Data),
    Pad = (4 - (Len rem 4)) rem 4,
    <<Code:32, Flags:8, Len:24, Data/binary, 0:(Pad * 8)>>.

%% diameter:call/4 returns whatever handle_answer/4 returns; hand back {ok, Msg}.
handle_answer(#diameter_packet{msg = Msg}, _Req, _Svc, _Peer) ->
    {ok, Msg}.

handle_error(Reason, _Req, _Svc, _Peer) ->
    {error, Reason}.

%% Inbound HSS-originated CLR: record it (keyed by IMSI) and answer CLA 2001.
handle_request(#diameter_packet{msg = ['CLR' | Avps]}, _Svc, {_Ref, Caps}) ->
    Imsi = maps:get('User-Name', Avps),
    ok = persistent_term:put({?MODULE, clr, Imsi}, Avps),
    #diameter_caps{origin_host = {OH, _}, origin_realm = {OR, _}} = Caps,
    {reply, ['CLA' | #{'Session-Id' => maps:get('Session-Id', Avps),
                       'Result-Code' => [2001],
                       'Auth-Session-State' => 1,
                       'Origin-Host' => OH,
                       'Origin-Realm' => OR}]};
handle_request(_Pkt, _Svc, _Peer) ->
    discard.
