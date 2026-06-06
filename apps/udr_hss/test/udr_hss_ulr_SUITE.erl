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
-module(udr_hss_ulr_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([first_ulr_returns_profile_registers_mme_no_clr/1,
         ulr_new_mme_emits_cancel_location/1,
         ulr_unknown_subscriber_returns_user_unknown/1,
         pur_clears_registration/1,
         pur_unknown_subscriber_returns_user_unknown/1]).

all() ->
    [first_ulr_returns_profile_registers_mme_no_clr,
     ulr_new_mme_emits_cancel_location,
     ulr_unknown_subscriber_returns_user_unknown,
     pur_clears_registration,
     pur_unknown_subscriber_returns_user_unknown].

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    Started = ?config(started, Config),
    [ application:stop(A) || A <- lists:reverse(Started) ],
    ok.

provision(Imsi) ->
    ok = udr_data:put_subscription_data(Imsi, #{<<"msisdn">> => <<"49170">>,
                                                <<"apn_config_profile">> => #{<<"context_id">> => 1}}).

ulr_req(Imsi, MmeHost) ->
    #{imsi => Imsi, mme_host => MmeHost, mme_realm => <<"epc.mnc001.mcc001">>,
      rat_type => eutran, visited_plmn => binary:decode_hex(<<"00f110">>)}.

first_ulr_returns_profile_registers_mme_no_clr(_Config) ->
    Imsi = <<"001010000000003">>,
    provision(Imsi),
    {ok, Ans, Effects} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    ?assertEqual([], Effects),
    Sub = maps:get(subscription_data, Ans),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-a">>, maps:get(<<"serving_mme_host">>, Reg)),
    ok.

ulr_new_mme_emits_cancel_location(_Config) ->
    Imsi = <<"001010000000004">>,
    provision(Imsi),
    {ok, _, []} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    {ok, _, Effects} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-b">>)),
    ?assertMatch([{cancel_location, #{imsi := Imsi, mme_host := <<"mme-a">>}}], Effects),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-b">>, maps:get(<<"serving_mme_host">>, Reg)),
    ok.

ulr_unknown_subscriber_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_ulr(ulr_req(<<"nope">>, <<"mme-a">>))),
    ok.

pur_clears_registration(_Config) ->
    Imsi = <<"001010000000005">>,
    provision(Imsi),
    {ok, _, []} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    {ok, #{}, []} = udr_hss:handle_pur(#{imsi => Imsi}),
    ?assertEqual({error, not_registered}, udr_data:get_3gpp_access_registration(Imsi)),
    ok.

pur_unknown_subscriber_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_pur(#{imsi => <<"nope-pur">>})),
    ok.
