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
-module(udr_data_integration_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([s6a_lifecycle/1]).

all() -> [s6a_lifecycle].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_db),
    [{started, Started} | Config].

end_per_suite(Config) ->
    [ application:stop(A) || A <- lists:reverse(?config(started, Config)) ],
    ok.

s6a_lifecycle(_Config) ->
    Imsi = <<"001010000000001">>,
    ok = udr_data:put_authentication_subscription(
           Imsi, #{<<"ki">> => <<"k">>, <<"opc">> => <<"o">>,
                   <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"a">>,
                   <<"sqn">> => 32}),
    ok = udr_data:put_subscription_data(
           Imsi, #{<<"msisdn">> => <<"49170">>,
                   <<"apn_config_profile">> => #{<<"context_id">> => 1}}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, Auth)),
    ?assertEqual({ok, 32}, udr_data:advance_sqn(Imsi, 5)),
    {ok, A2} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(37, maps:get(<<"sqn">>, A2)),
    {ok, Am} = udr_data:get_am_subscription(Imsi),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Am)),
    ?assertEqual({error, not_registered}, udr_data:get_3gpp_access_registration(Imsi)),
    ok = udr_data:put_3gpp_access_registration(
           Imsi, #{<<"serving_mme_host">> => <<"mme-a">>, <<"status">> => <<"registered">>}),
    {ok, R1} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-a">>, maps:get(<<"serving_mme_host">>, R1)),
    ok = udr_data:put_3gpp_access_registration(
           Imsi, #{<<"serving_mme_host">> => <<"mme-b">>, <<"status">> => <<"registered">>}),
    {ok, R2} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-b">>, maps:get(<<"serving_mme_host">>, R2)),
    ok = udr_data:delete_3gpp_access_registration(Imsi),
    ?assertEqual({error, not_registered}, udr_data:get_3gpp_access_registration(Imsi)),
    ok.
