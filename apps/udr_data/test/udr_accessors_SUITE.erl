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
-module(udr_accessors_SUITE).
-moduledoc "Pure-function tests for the per-aggregate accessor modules.\n"
           "No backend or DB process is needed — all tests exercise `from_doc/1`,\n"
           "`to_doc/1`, and invariant Funs in isolation.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0]).

%% udr_auth tests
-export([auth_roundtrip_stamps_schema_version/1,
         auth_missing_optional_fields_default/1,
         auth_upgrade_on_read_absent_version/1,
         auth_upgrade_on_read_old_version/1,
         auth_advance_sqn_fun_increments/1,
         auth_advance_sqn_fun_start_derivable/1,
         auth_repair_sqn_fun_sets/1]).

%% udr_subscription tests
-export([sub_roundtrip_stamps_schema_version/1,
         sub_missing_optional_fields_default/1,
         sub_upgrade_on_read_absent_version/1,
         sub_am_view_excludes_apn/1,
         sub_sm_view_only_apn/1]).

%% udr_registration tests
-export([reg_roundtrip_stamps_schema_version/1,
         reg_missing_optional_fields_default/1,
         reg_upgrade_on_read_absent_version/1,
         reg_is_purged_true/1,
         reg_is_purged_false/1,
         reg_is_purged_default/1,
         reg_serving_mme_present/1,
         reg_serving_mme_absent/1,
         reg_serving_mme_empty/1]).

all() ->
    [%% udr_auth
     auth_roundtrip_stamps_schema_version,
     auth_missing_optional_fields_default,
     auth_upgrade_on_read_absent_version,
     auth_upgrade_on_read_old_version,
     auth_advance_sqn_fun_increments,
     auth_advance_sqn_fun_start_derivable,
     auth_repair_sqn_fun_sets,
     %% udr_subscription
     sub_roundtrip_stamps_schema_version,
     sub_missing_optional_fields_default,
     sub_upgrade_on_read_absent_version,
     sub_am_view_excludes_apn,
     sub_sm_view_only_apn,
     %% udr_registration
     reg_roundtrip_stamps_schema_version,
     reg_missing_optional_fields_default,
     reg_upgrade_on_read_absent_version,
     reg_is_purged_true,
     reg_is_purged_false,
     reg_is_purged_default,
     reg_serving_mme_present,
     reg_serving_mme_absent,
     reg_serving_mme_empty].

%%==============================================================================
%% udr_auth tests
%%==============================================================================

auth_roundtrip_stamps_schema_version(_Config) ->
    Input = #{ <<"ki">> => <<"abc">>, <<"opc">> => <<"def">>,
               <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"0001">>,
               <<"sqn">> => 42 },
    Doc = udr_auth:to_doc(Input),
    ?assertEqual(1, maps:get(<<"schema_version">>, Doc)),
    Roundtrip = udr_auth:from_doc(Doc),
    ?assertEqual(1, maps:get(<<"schema_version">>, Roundtrip)),
    ?assertEqual(<<"abc">>, maps:get(<<"ki">>, Roundtrip)),
    ?assertEqual(42, maps:get(<<"sqn">>, Roundtrip)),
    ok.

auth_missing_optional_fields_default(_Config) ->
    %% A doc with no fields: from_doc/1 should supply all defaults.
    Map = udr_auth:from_doc(#{ <<"schema_version">> => 1 }),
    ?assertEqual(1,            maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<>>,         maps:get(<<"ki">>,        Map)),
    ?assertEqual(<<>>,         maps:get(<<"opc">>,       Map)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, Map)),
    ?assertEqual(<<>>,         maps:get(<<"amf">>,       Map)),
    ?assertEqual(0,            maps:get(<<"sqn">>,       Map)),
    ok.

auth_upgrade_on_read_absent_version(_Config) ->
    %% A legacy doc with no schema_version should be normalised.
    LegacyDoc = #{ <<"ki">> => <<"k">>, <<"sqn">> => 100 },
    Map = udr_auth:from_doc(LegacyDoc),
    ?assertEqual(1,   maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<"k">>, maps:get(<<"ki">>, Map)),
    ?assertEqual(100, maps:get(<<"sqn">>, Map)),
    %% Optional fields not present in the legacy doc receive defaults.
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, Map)),
    ok.

auth_upgrade_on_read_old_version(_Config) ->
    %% A doc with schema_version = 0 (pre-v1) is treated like a legacy doc.
    OldDoc = #{ <<"schema_version">> => 0, <<"ki">> => <<"k2">>, <<"sqn">> => 7 },
    Map = udr_auth:from_doc(OldDoc),
    ?assertEqual(1, maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<"k2">>, maps:get(<<"ki">>, Map)),
    ?assertEqual(7, maps:get(<<"sqn">>, Map)),
    ok.

auth_advance_sqn_fun_increments(_Config) ->
    Doc = #{ <<"schema_version">> => 1, <<"sqn">> => 1000 },
    Fun = udr_auth:advance_sqn_fun(5),
    {ok, NewDoc} = Fun(Doc),
    ?assertEqual(1005, maps:get(<<"sqn">>, NewDoc)),
    ok.

auth_advance_sqn_fun_start_derivable(_Config) ->
    %% Verify that start = new_sqn - N (as documented).
    N = 10,
    Doc = #{ <<"schema_version">> => 1, <<"sqn">> => 500 },
    Fun = udr_auth:advance_sqn_fun(N),
    {ok, NewDoc} = Fun(Doc),
    NewSqn = maps:get(<<"sqn">>, NewDoc),
    Start  = NewSqn - N,
    ?assertEqual(500, Start),
    ?assertEqual(510, NewSqn),
    ok.

auth_repair_sqn_fun_sets(_Config) ->
    Doc = #{ <<"schema_version">> => 1, <<"sqn">> => 999 },
    Fun = udr_auth:repair_sqn_fun(42),
    {ok, NewDoc} = Fun(Doc),
    ?assertEqual(42, maps:get(<<"sqn">>, NewDoc)),
    ok.

%%==============================================================================
%% udr_subscription tests
%%==============================================================================

sub_roundtrip_stamps_schema_version(_Config) ->
    Input = #{ <<"msisdn">> => <<"49170">>,
               <<"subscriber_status">> => <<"SERVICE_GRANTED">>,
               <<"ambr">> => #{<<"ul">> => 100, <<"dl">> => 200},
               <<"apn_config_profile">> => #{<<"context_id">> => 1} },
    Doc = udr_subscription:to_doc(Input),
    ?assertEqual(1, maps:get(<<"schema_version">>, Doc)),
    Roundtrip = udr_subscription:from_doc(Doc),
    ?assertEqual(1, maps:get(<<"schema_version">>, Roundtrip)),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Roundtrip)),
    ?assertEqual(#{<<"context_id">> => 1},
                 maps:get(<<"apn_config_profile">>, Roundtrip)),
    ok.

sub_missing_optional_fields_default(_Config) ->
    Map = udr_subscription:from_doc(#{ <<"schema_version">> => 1 }),
    ?assertEqual(1,                    maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<>>,                 maps:get(<<"msisdn">>, Map)),
    ?assertEqual(<<"SERVICE_GRANTED">>, maps:get(<<"subscriber_status">>, Map)),
    ?assertEqual(#{},                  maps:get(<<"ambr">>, Map)),
    ?assertEqual(#{},                  maps:get(<<"apn_config_profile">>, Map)),
    ok.

sub_upgrade_on_read_absent_version(_Config) ->
    LegacyDoc = #{ <<"msisdn">> => <<"1234">>,
                   <<"apn_config_profile">> => #{<<"context_id">> => 2} },
    Map = udr_subscription:from_doc(LegacyDoc),
    ?assertEqual(1, maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<"1234">>, maps:get(<<"msisdn">>, Map)),
    ?assertEqual(#{<<"context_id">> => 2},
                 maps:get(<<"apn_config_profile">>, Map)),
    ok.

sub_am_view_excludes_apn(_Config) ->
    Input = #{ <<"msisdn">> => <<"49170">>,
               <<"subscriber_status">> => <<"SERVICE_GRANTED">>,
               <<"ambr">> => #{},
               <<"apn_config_profile">> => #{<<"context_id">> => 1} },
    Map = udr_subscription:from_doc(udr_subscription:to_doc(Input)),
    Am  = udr_subscription:am_view(Map),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Am)),
    ?assertEqual(error, maps:find(<<"apn_config_profile">>, Am)),
    ok.

sub_sm_view_only_apn(_Config) ->
    Input = #{ <<"msisdn">> => <<"49170">>,
               <<"apn_config_profile">> => #{<<"context_id">> => 3} },
    Map = udr_subscription:from_doc(udr_subscription:to_doc(Input)),
    Sm  = udr_subscription:sm_view(Map),
    ?assertEqual(#{<<"context_id">> => 3},
                 maps:get(<<"apn_config_profile">>, Sm)),
    ?assertEqual(error, maps:find(<<"msisdn">>, Sm)),
    %% schema_version is always included in the SM view.
    ?assertEqual(1, maps:get(<<"schema_version">>, Sm)),
    ok.

%%==============================================================================
%% udr_registration tests
%%==============================================================================

reg_roundtrip_stamps_schema_version(_Config) ->
    Input = #{ <<"serving_mme_host">>  => <<"mme1.example.com">>,
               <<"serving_mme_realm">> => <<"example.com">>,
               <<"ue_purged">>         => false,
               <<"status">>            => <<"registered">> },
    Doc = udr_registration:to_doc(Input),
    ?assertEqual(1, maps:get(<<"schema_version">>, Doc)),
    Roundtrip = udr_registration:from_doc(Doc),
    ?assertEqual(1, maps:get(<<"schema_version">>, Roundtrip)),
    ?assertEqual(<<"mme1.example.com">>, maps:get(<<"serving_mme_host">>, Roundtrip)),
    ok.

reg_missing_optional_fields_default(_Config) ->
    Map = udr_registration:from_doc(#{ <<"schema_version">> => 1 }),
    ?assertEqual(1,     maps:get(<<"schema_version">>,   Map)),
    ?assertEqual(<<>>,  maps:get(<<"serving_mme_host">>, Map)),
    ?assertEqual(<<>>,  maps:get(<<"serving_mme_realm">>, Map)),
    ?assertEqual(false, maps:get(<<"ue_purged">>,         Map)),
    ?assertEqual(<<>>,  maps:get(<<"status">>,            Map)),
    ok.

reg_upgrade_on_read_absent_version(_Config) ->
    LegacyDoc = #{ <<"serving_mme_host">> => <<"old-mme">>,
                   <<"ue_purged">> => true },
    Map = udr_registration:from_doc(LegacyDoc),
    ?assertEqual(1,          maps:get(<<"schema_version">>, Map)),
    ?assertEqual(<<"old-mme">>, maps:get(<<"serving_mme_host">>, Map)),
    ?assertEqual(true,       maps:get(<<"ue_purged">>, Map)),
    ok.

reg_is_purged_true(_Config) ->
    Map = udr_registration:from_doc(#{ <<"ue_purged">> => true }),
    ?assert(udr_registration:is_purged(Map)),
    ok.

reg_is_purged_false(_Config) ->
    Map = udr_registration:from_doc(#{ <<"ue_purged">> => false }),
    ?assertNot(udr_registration:is_purged(Map)),
    ok.

reg_is_purged_default(_Config) ->
    %% When ue_purged is absent the default is false.
    Map = udr_registration:from_doc(#{}),
    ?assertNot(udr_registration:is_purged(Map)),
    ok.

reg_serving_mme_present(_Config) ->
    Map = udr_registration:from_doc(
            #{ <<"serving_mme_host">>  => <<"mme1">>,
               <<"serving_mme_realm">> => <<"epc.mnc001.mcc001.3gppnetwork.org">> }),
    ?assertEqual({<<"mme1">>, <<"epc.mnc001.mcc001.3gppnetwork.org">>},
                 udr_registration:serving_mme(Map)),
    ok.

reg_serving_mme_absent(_Config) ->
    %% from_doc/1 defaults serving_mme_host to <<>>, so serving_mme/1 returns undefined.
    Map = udr_registration:from_doc(#{}),
    ?assertEqual(undefined, udr_registration:serving_mme(Map)),
    ok.

reg_serving_mme_empty(_Config) ->
    Map = udr_registration:from_doc(#{ <<"serving_mme_host">> => <<>> }),
    ?assertEqual(undefined, udr_registration:serving_mme(Map)),
    ok.
