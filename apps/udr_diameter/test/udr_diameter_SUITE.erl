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
-export([air/1, ulr_then_clr/1, pur/1]).

all() -> [air, ulr_then_clr, pur].

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
    ?assertEqual(true, udr_diameter_test_mme:received_clr(Imsi, 2000)).

pur(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, ['PUA' | Ans]} = udr_diameter_test_mme:pur(Imsi),
    ?assertEqual([2001], maps:get('Result-Code', Ans)).
