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
-module(udr_diameter_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([air/1, ulr_then_clr/1, pur/1, nor/1,
         common_dictionary_is_rfc6733/1, decode_errors_answer_not_crash/1]).

all() -> [air, ulr_then_clr, pur, nor,
          common_dictionary_is_rfc6733, decode_errors_answer_not_crash].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, _} = application:ensure_all_started(udr_hss),
    Imsi = <<"001010000000001">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
           <<"ki">> => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
           <<"opc">> => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
           <<"algorithm">> => <<"milenage">>,
           <<"amf">> => binary:decode_hex(<<"b9b9">>), <<"sqn">> => 0}),
    ok = udr_data:put_subscription_data(Imsi, #{<<"apn_config_profile">> => #{<<"context_id">> => 1}}),
    Port = 13868,
    %% Load before set_env: ensure_all_started/1 calls application:load/1, which
    %% merges the .app file env over a not-yet-loaded app's set_env values -- so
    %% the listen port must be set AFTER the app is loaded for it to take effect.
    ok = application:load(udr_diameter),
    application:set_env(udr_diameter, listen, [{tcp, {127,0,0,1}, Port}]),
    {ok, _} = application:ensure_all_started(udr_diameter),
    {ok, _Mme} = udr_diameter_test_mme:start(Port),
    [{imsi, Imsi} | Config].

end_per_suite(_Config) ->
    _ = udr_diameter_test_mme:stop(),
    _ = application:stop(udr_diameter),
    ok.

air(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, ['AIA' | Ans]} = udr_diameter_test_mme:air(Imsi, 2),
    ?assertEqual([2001], maps:get('Result-Code', Ans)),
    [#{'E-UTRAN-Vector' := EVs}] = maps:get('Authentication-Info', Ans),
    ?assertEqual(2, length(EVs)).

ulr_then_clr(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, ['ULA' | _]} = udr_diameter_test_mme:ulr(Imsi, <<"mme-a">>),
    {ok, ['ULA' | _]} = udr_diameter_test_mme:ulr(Imsi, <<"mme-b">>),
    ?assertEqual(true, udr_diameter_test_mme:received_clr(Imsi, 2000)),
    Clr = udr_diameter_test_mme:recorded_clr(Imsi),
    %% ULR-Flags carried 0 (no Initial-Attach) -> MME Update Procedure (0).
    ?assertEqual(0, maps:get('Cancellation-Type', Clr)),
    ok.

pur(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, ['PUA' | Ans]} = udr_diameter_test_mme:pur(Imsi),
    ?assertEqual([2001], maps:get('Result-Code', Ans)).

nor(Config) ->
    Imsi = ?config(imsi, Config),
    %% Register this connection's MME (mme-a) as the serving node, then notify.
    {ok, ['ULA' | _]} = udr_diameter_test_mme:ulr(Imsi, <<"mme-a">>),
    {ok, ['NOA' | Ans]} = udr_diameter_test_mme:nor(Imsi),
    ?assertEqual([2001], maps:get('Result-Code', Ans)),
    ok.

%% The HSS must register the RFC 6733 base as its common application (App-Id 0)
%% so diameter's negotiated common dictionary ("Dict0") is RFC 6733, not the
%% built-in default RFC 3588. This is the invariant that makes returning a 5xxx
%% Result-Code via {answer_message, _} legal (RFC 3588 permits only 3xxx). Guards
%% against silently dropping the base-app registration in udr_diameter_srv.
common_dictionary_is_rfc6733(_Config) ->
    Apps = diameter:service_info(udr_diameter, applications),
    Common = [A || A <- Apps, proplists:get_value(id, A) =:= 0],
    ?assertMatch([_], Common),
    [App] = Common,
    ?assertEqual(diameter_gen_base_rfc6733,
                 proplists:get_value(dictionary, App)).

%% End-to-end regression for the AIR crash: a request that fails to decode must
%% yield a clean Diameter error answer, not crash the HSS request process. The MME
%% sends an AIR carrying an unknown mandatory AVP; diameter answers it itself
%% (s6a app configured {request_errors, answer}) with the actual decode error,
%% DIAMETER_AVP_UNSUPPORTED (5001), in a bare 'answer-message' with a Failed-AVP.
%%
%% The original bug: the s6a app's then handle_request/3 answered such requests
%% with {answer_message, 5005}, which the OTP stack rejected as an invalid_return
%% against the (then-default) RFC 3588 common dictionary, crashing the request
%% process so the MME's AIR timed out. A 5xxx code is admissible in an answer-
%% message only when the common dictionary is not the RFC 3588 base (?BASE /=
%% Dict0) -- the property the RFC 6733 common-app registration establishes. This
%% case fails (no clean 5001 'answer-message') if either that registration or the
%% {request_errors, answer} option regresses.
decode_errors_answer_not_crash(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, ['answer-message' | Ans]} = udr_diameter_test_mme:bad_air(Imsi),
    ?assertEqual(5001, maps:get('Result-Code', Ans)).
