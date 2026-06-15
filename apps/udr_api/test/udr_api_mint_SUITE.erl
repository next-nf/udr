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
-module(udr_api_mint_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([stores_identity/1, opc_matches_derivation/1, rejects_double_provision/1,
         op_not_configured/1, op_misconfigured/1, minted_creds_authenticate/1,
         honors_amf_override/1, passes_through_profile/1]).

%% Fixed non-zero test OP (16 bytes).
-define(OP, binary:decode_hex(<<"000102030405060708090a0b0c0d0e0f">>)).

all() ->
    [stores_identity, opc_matches_derivation, rejects_double_provision,
     op_not_configured, op_misconfigured, minted_creds_authenticate,
     honors_amf_override, passes_through_profile].

%% IMSIs this suite provisions. The udr_db store is a node-wide table shared
%% across every suite in the run, so we clear these before each case: other
%% suites (e.g. udr_hss_air_SUITE) seed auth records for 001010000000010/011,
%% which would otherwise trip this suite's double-provision guard.
imsis() ->
    [<<"001010000000010">>, <<"001010000000011">>, <<"001010000000012">>,
     <<"001010000000013">>, <<"001010000000014">>, <<"001010000000015">>,
     <<"001010000000016">>, <<"001010000000017">>].

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    application:set_env(udr_api, op, ?OP),
    application:set_env(udr_api, default_amf, binary:decode_hex(<<"b9b9">>)),
    %% Start the data/crypto/cluster closure plus the HSS engine. We deliberately
    %% do not start the udr_api application itself: udr_api_mint is a library
    %% module (loaded by ct), and starting udr_api would boot the Cowboy listener
    %% this suite has no use for.
    {ok, Started1} = application:ensure_all_started(udr_hss),
    {ok, Started2} = application:ensure_all_started(udr_cluster),
    {ok, Started3} = application:ensure_all_started(udr_crypto),
    %% Apps are up (udr_db live); drop any records left by an earlier suite.
    [ begin
          udr_data:delete_authentication_subscription(I),
          udr_data:delete_subscription_data(I)
      end || I <- imsis() ],
    [{started, Started1 ++ Started2 ++ Started3} | Config].

end_per_testcase(_TestCase, Config) ->
    [ application:stop(A) || A <- lists:reverse(?config(started, Config)) ],
    ok.

stores_identity(_Config) ->
    Imsi = <<"001010000000011">>,
    {ok, Res} = udr_api_mint:provision(#{imsi   => Imsi,
                                         msisdn => <<"49170">>,
                                         iccid  => <<"8988001000000000011">>}),
    ?assertEqual(Imsi, maps:get(imsi, Res)),
    ?assertEqual(<<"8988001000000000011">>, maps:get(iccid, Res)),
    {ok, Sub} = udr_data:get_subscription_data(Imsi),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    ?assertEqual(<<"8988001000000000011">>, maps:get(<<"iccid">>, Sub)),
    ok.

rejects_double_provision(_Config) ->
    Imsi = <<"001010000000012">>,
    Req  = #{imsi => Imsi, msisdn => <<"49170">>, iccid => <<"8988001000000000012">>},
    {ok, _}     = udr_api_mint:provision(Req),
    {ok, Auth1} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual({error, already_provisioned}, udr_api_mint:provision(Req)),
    {ok, Auth2} = udr_data:get_authentication_subscription(Imsi),
    %% The original Ki must be untouched by the rejected re-provision.
    ?assertEqual(maps:get(<<"ki">>, Auth1), maps:get(<<"ki">>, Auth2)),
    ok.

op_not_configured(_Config) ->
    application:unset_env(udr_api, op),
    ?assertEqual(
       {error, op_not_configured},
       udr_api_mint:provision(#{imsi   => <<"001010000000013">>,
                                msisdn => <<"49170">>,
                                iccid  => <<"8988001000000000013">>})),
    ok.

op_misconfigured(_Config) ->
    application:set_env(udr_api, op, <<1,2,3>>),  %% not 16 bytes
    ?assertEqual(
       {error, op_misconfigured},
       udr_api_mint:provision(#{imsi   => <<"001010000000015">>,
                                msisdn => <<"49170">>,
                                iccid  => <<"8988001000000000015">>})),
    ok.

minted_creds_authenticate(_Config) ->
    Imsi = <<"001010000000014">>,
    {ok, _} = udr_api_mint:provision(#{imsi   => Imsi,
                                       msisdn => <<"49170">>,
                                       iccid  => <<"8988001000000000014">>}),
    {ok, Ans, Effects} =
        udr_hss:handle_air(#{imsi         => Imsi,
                             visited_plmn => binary:decode_hex(<<"00f110">>),
                             num_vectors  => 1}),
    ?assertEqual([], Effects),
    [V] = maps:get(vectors, Ans),
    ?assertEqual(16, byte_size(maps:get(rand, V))),
    ?assertEqual(16, byte_size(maps:get(autn, V))),
    ?assertEqual(8,  byte_size(maps:get(xres, V))),
    ?assertEqual(32, byte_size(maps:get(kasme, V))),
    %% Provisioning starts SQN at 0; one AIR vector advances it to 1.
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(1, maps:get(<<"sqn">>, Auth)),
    ok.

opc_matches_derivation(_Config) ->
    Imsi = <<"001010000000010">>,
    {ok, _} = udr_api_mint:provision(#{imsi   => Imsi,
                                       msisdn => <<"49170">>,
                                       iccid  => <<"8988001000000000010">>}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    Ki  = maps:get(<<"ki">>, Auth),
    OPc = maps:get(<<"opc">>, Auth),
    ?assertEqual(16, byte_size(Ki)),
    ?assertNotEqual(?OP, Ki),
    ?assertEqual(udr_crypto:opc(milenage, Ki, ?OP), OPc),
    ?assertEqual(0, maps:get(<<"sqn">>, Auth)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, Auth)),
    ?assertEqual(binary:decode_hex(<<"b9b9">>), maps:get(<<"amf">>, Auth)),
    ok.

honors_amf_override(_Config) ->
    Imsi = <<"001010000000016">>,
    {ok, _} = udr_api_mint:provision(#{imsi   => Imsi,
                                       msisdn => <<"49170">>,
                                       iccid  => <<"8988001000000000016">>,
                                       amf    => <<1,2>>}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(<<1,2>>, maps:get(<<"amf">>, Auth)),
    ok.

passes_through_profile(_Config) ->
    Imsi = <<"001010000000017">>,
    {ok, _} = udr_api_mint:provision(#{imsi    => Imsi,
                                       msisdn  => <<"49170">>,
                                       iccid   => <<"8988001000000000017">>,
                                       profile => #{<<"apn_config_profile">> => #{<<"x">> => 1}}}),
    {ok, Sub} = udr_data:get_subscription_data(Imsi),
    ?assertEqual(#{<<"x">> => 1}, maps:get(<<"apn_config_profile">>, Sub)),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    ?assertEqual(<<"8988001000000000017">>, maps:get(<<"iccid">>, Sub)),
    ok.
