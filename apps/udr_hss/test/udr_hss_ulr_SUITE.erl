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
         pur_from_registered_mme_marks_purged_and_freezes/1,
         pur_from_other_mme_no_freeze/1,
         pur_unknown_subscriber_returns_user_unknown/1,
         ulr_initial_attach_uses_initial_attach_cancellation/1,
         ulr_skip_subscriber_data_omits_profile/1]).

all() ->
    [first_ulr_returns_profile_registers_mme_no_clr,
     ulr_new_mme_emits_cancel_location,
     ulr_unknown_subscriber_returns_user_unknown,
     pur_from_registered_mme_marks_purged_and_freezes,
     pur_from_other_mme_no_freeze,
     pur_unknown_subscriber_returns_user_unknown,
     ulr_initial_attach_uses_initial_attach_cancellation,
     ulr_skip_subscriber_data_omits_profile].

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
    ?assertMatch([{cancel_location, #{imsi := Imsi, mme_host := <<"mme-a">>,
                                      cancellation_type := mme_update_procedure}}], Effects),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-b">>, maps:get(<<"serving_mme_host">>, Reg)),
    ok.

ulr_unknown_subscriber_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_ulr(ulr_req(<<"nope">>, <<"mme-a">>))),
    ok.

pur_from_registered_mme_marks_purged_and_freezes(_Config) ->
    Imsi = <<"001010000000005">>,
    provision(Imsi),
    {ok, _, []} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    {ok, Ans, []} = udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-a">>}),
    ?assertEqual(true, maps:get(freeze_m_tmsi, Ans)),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(true, maps:get(<<"ue_purged">>, Reg)),
    ok.

pur_from_other_mme_no_freeze(_Config) ->
    Imsi = <<"001010000000008">>,
    provision(Imsi),
    {ok, _, []} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    {ok, Ans, []} = udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-x">>}),
    ?assertEqual(false, maps:get(freeze_m_tmsi, Ans)),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(false, maps:get(<<"ue_purged">>, Reg, false)),
    ok.

pur_unknown_subscriber_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_pur(#{imsi => <<"nope-pur">>})),
    ok.

ulr_initial_attach_uses_initial_attach_cancellation(_Config) ->
    Imsi = <<"001010000000006">>,
    provision(Imsi),
    {ok, _, []} = udr_hss:handle_ulr(ulr_req(Imsi, <<"mme-a">>)),
    Req = (ulr_req(Imsi, <<"mme-b">>))#{initial_attach => true},
    {ok, _, Effects} = udr_hss:handle_ulr(Req),
    ?assertMatch([{cancel_location, #{cancellation_type := initial_attach_procedure}}], Effects),
    ok.

ulr_skip_subscriber_data_omits_profile(_Config) ->
    Imsi = <<"001010000000007">>,
    provision(Imsi),
    Req = (ulr_req(Imsi, <<"mme-a">>))#{skip_subscriber_data => true},
    {ok, Ans, _} = udr_hss:handle_ulr(Req),
    ?assertEqual(error, maps:find(subscription_data, Ans)),
    ok.
