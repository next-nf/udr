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
-module(udr_diameter_s6a).
-moduledoc "diameter_app callback for S6a. Translates each request once into udr_hss's\n"
           "semantic map, calls the handler, translates the answer back, and replies;\n"
           "executes the cancel_location effect by originating a CLR (fire-and-forget).".
-behaviour(diameter_app).
-include_lib("diameter/include/diameter.hrl").
-include_lib("opentelemetry_api/include/otel_tracer.hrl").
-include_lib("opentelemetry_api/include/opentelemetry.hrl").

-export([peer_up/3, peer_down/3, pick_peer/4, prepare_request/3,
         prepare_retransmit/3, handle_answer/4, handle_error/4, handle_request/3]).

%% The OTP diameter map-message form is the improper list [MsgName | AvpMap];
%% dialyzer flags it as improper_list, so suppress that category for the
%% functions that build such messages.
-dialyzer({no_improper_lists, [reply/5, run_effect/1]}).

-define(SVC, udr_diameter).

-spec peer_up(term(), term(), term()) -> term().
peer_up(_Svc, _Peer, State)   -> State.

-spec peer_down(term(), term(), term()) -> term().
peer_down(_Svc, _Peer, State) -> State.

-spec pick_peer([term()], [term()], term(), term()) -> {ok, term()} | false.
pick_peer([Peer | _], _, _Svc, _St) -> {ok, Peer};
pick_peer([], _, _Svc, _St)         -> false.

-spec prepare_request(term(), term(), term()) -> {send, term()}.
prepare_request(Pkt, _Svc, _Peer)    -> {send, Pkt}.

-spec prepare_retransmit(term(), term(), term()) -> {send, term()}.
prepare_retransmit(Pkt, _Svc, _Peer) -> {send, Pkt}.

-spec handle_answer(term(), term(), term(), term()) -> ok.
handle_answer(_Pkt, _Req, _Svc, _Peer) -> ok.    %% CLA absorbed

-spec handle_error(term(), term(), term(), term()) -> ok.
handle_error(_Reason, _Req, _Svc, _Peer) -> ok.

%% Requests that fail to decode never reach here: the service is configured with
%% {request_errors, answer} (see udr_diameter_srv), so diameter answers them
%% itself with the actual decode error and a Failed-AVP. This callback only sees
%% cleanly-decoded requests.
-spec handle_request(#diameter_packet{}, term(), term()) ->
    {reply, list()} | discard.
handle_request(#diameter_packet{msg = [Cmd | Avps]}, _Svc, {_Ref, Caps})
  when Cmd =:= 'AIR'; Cmd =:= 'ULR'; Cmd =:= 'PUR'; Cmd =:= 'NOR' ->
    Start = erlang:monotonic_time(),
    ?with_span(span_name(Cmd), #{kind => ?SPAN_KIND_SERVER},
        fun(_) ->
            ?set_attributes(#{'s6a.command' => Cmd,
                              's6a.imsi' => maps:get('User-Name', Avps, undefined)}),
            {Reply, Result} = dispatch(Cmd, Avps, Caps),
            Class = result_class(Result),
            ?set_attributes(#{'s6a.result' => Class}),
            udr_otel:record_s6a(Cmd, Class, erlang:monotonic_time() - Start),
            Reply
        end);
handle_request(_Pkt, _Svc, _Peer) ->
    discard.

span_name('AIR') -> <<"s6a.AIR">>;
span_name('ULR') -> <<"s6a.ULR">>;
span_name('PUR') -> <<"s6a.PUR">>;
span_name('NOR') -> <<"s6a.NOR">>.

dispatch('AIR', Avps, Caps) ->
    R = udr_hss:handle_air(udr_diameter_codec:decode_air(Avps)),
    {reply('AIA', Avps, Caps, udr_diameter_codec:encode_air_answer(strip_effects(R)), effects(R)), R};
dispatch('ULR', Avps, Caps) ->
    R = udr_hss:handle_ulr(udr_diameter_codec:decode_ulr(Avps)),
    {reply('ULA', Avps, Caps, udr_diameter_codec:encode_ulr_answer(strip_effects(R)), effects(R)), R};
dispatch('PUR', Avps, Caps) ->
    R = udr_hss:handle_pur(udr_diameter_codec:decode_pur(Avps)),
    {reply('PUA', Avps, Caps, udr_diameter_codec:encode_pua_answer(strip_effects(R)), effects(R)), R};
dispatch('NOR', Avps, Caps) ->
    R = udr_hss:handle_nor(udr_diameter_codec:decode_nor(Avps)),
    {reply('NOA', Avps, Caps, udr_diameter_codec:encode_noa_answer(strip_effects(R)), effects(R)), R}.

result_class({ok, _, _})      -> success;
result_class({error, Reason}) -> Reason.

%% udr_hss returns {ok, Answer, Effects}; encoders take {ok, Answer} | {error, _}.
strip_effects({ok, Answer, _Effects}) -> {ok, Answer};
strip_effects({error, _} = E)         -> E.
effects({ok, _A, Effects}) -> Effects;
effects(_)                 -> [].

reply(Name, #{'Session-Id' := Sid}, Caps, AnswerAvps, Effects) ->
    run_effects(Effects),
    #diameter_caps{origin_host = {OH, _}, origin_realm = {OR, _}} = Caps,
    Common = #{'Session-Id' => Sid,
               'Auth-Session-State' => 1,
               'Origin-Host' => OH, 'Origin-Realm' => OR},
    {reply, [Name | maps:merge(Common, AnswerAvps)]}.

run_effects(Effects) -> lists:foreach(fun run_effect/1, Effects).

run_effect({cancel_location, Info}) ->
    %% Capture the current OTel context so a future child span can link the CLR
    %% to its originating ULR. The CLR uses diameter:call [detach], so it runs
    %% out of band; the full child span is future work.
    Ctx = otel_ctx:get_current(),
    _ = Ctx,
    {ok, OH} = application:get_env(udr_diameter, origin_host),
    {ok, OR} = application:get_env(udr_diameter, origin_realm),
    Clr0 = udr_diameter_codec:clr_request(Info),
    Clr = Clr0#{'Session-Id' => list_to_binary(diameter:session_id(OH)),
                'Auth-Session-State' => 1,
                'Origin-Host'  => list_to_binary(OH),
                'Origin-Realm' => list_to_binary(OR)},
    #{mme_host := Host, mme_realm := Realm} = Info,
    Filter = {filter, {all, [{host, Host}, {realm, Realm}]}},
    _ = diameter:call(?SVC, s6a, ['CLR' | Clr], [detach, Filter]),
    ok.
