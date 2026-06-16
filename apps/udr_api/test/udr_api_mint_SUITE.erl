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
         honors_amf_override/1, passes_through_profile/1,
         preserves_existing_profile/1, rejects_invalid_identity/1,
         rejects_missing_keys/1, rejects_invalid_amf/1, amf_not_configured/1,
         mints_tuak/1, tuak_top_not_configured/1, rejects_unsupported_algorithm/1]).

%% Fixed non-zero test OP (16 bytes) and TOP (32 bytes, TUAK).
-define(OP, binary:decode_hex(<<"000102030405060708090a0b0c0d0e0f">>)).
-define(TOP, binary:decode_hex(<<"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f">>)).

all() ->
    [stores_identity, opc_matches_derivation, rejects_double_provision,
     op_not_configured, op_misconfigured, minted_creds_authenticate,
     honors_amf_override, passes_through_profile,
     preserves_existing_profile, rejects_invalid_identity,
     rejects_missing_keys, rejects_invalid_amf, amf_not_configured,
     mints_tuak, tuak_top_not_configured, rejects_unsupported_algorithm].

%% Single source of truth for each case's IMSI. The udr_db ETS store is a
%% node-wide table shared by every suite in a `rebar3 ct` run; cross-suite
%% isolation is handled centrally by udr_db_reset_cth, which flushes a leaked
%% store between suites. Each case still uses a distinct IMSI so the cases
%% within this suite don't collide with one another. Reading the IMSI from here
%% (via ?config(imsi, _)) rather than hardcoding it per case means there is no
%% list to keep in sync, and a case absent from this map fails loudly with a
%% function_clause instead of silently skipping.
imsi(stores_identity)           -> <<"001010000000011">>;
imsi(opc_matches_derivation)    -> <<"001010000000010">>;
imsi(rejects_double_provision)  -> <<"001010000000012">>;
imsi(op_not_configured)         -> <<"001010000000013">>;
imsi(minted_creds_authenticate) -> <<"001010000000014">>;
imsi(op_misconfigured)          -> <<"001010000000015">>;
imsi(honors_amf_override)       -> <<"001010000000016">>;
imsi(passes_through_profile)    -> <<"001010000000017">>;
imsi(preserves_existing_profile)-> <<"001010000000018">>;
imsi(rejects_invalid_identity)  -> <<"001010000000019">>;
imsi(rejects_missing_keys)      -> <<"001010000000020">>;
imsi(rejects_invalid_amf)       -> <<"001010000000021">>;
imsi(amf_not_configured)        -> <<"001010000000022">>;
imsi(mints_tuak)                -> <<"001010000000023">>;
imsi(tuak_top_not_configured)   -> <<"001010000000024">>;
imsi(rejects_unsupported_algorithm) -> <<"001010000000025">>.

init_per_testcase(TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    application:set_env(udr_api, op, ?OP),
    application:set_env(udr_api, top, ?TOP),
    application:set_env(udr_api, default_amf, binary:decode_hex(<<"b9b9">>)),
    %% Start the data/crypto/cluster closure plus the HSS engine. We deliberately
    %% do not start the udr_api application itself: udr_api_mint is a library
    %% module (loaded by ct), and starting udr_api would boot the Cowboy listener
    %% this suite has no use for.
    {ok, Started1} = application:ensure_all_started(udr_hss),
    {ok, Started2} = application:ensure_all_started(udr_cluster),
    {ok, Started3} = application:ensure_all_started(udr_crypto),
    Imsi = imsi(TestCase),
    [{imsi, Imsi}, {started, Started1 ++ Started2 ++ Started3} | Config].

end_per_testcase(_TestCase, Config) ->
    [ application:stop(A) || A <- lists:reverse(?config(started, Config)) ],
    ok.

stores_identity(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, Res} = udr_api_mint:provision(#{imsi   => Imsi,
                                         msisdn => <<"49170">>,
                                         iccid  => <<"8988001000000000011">>}),
    ?assertEqual(Imsi, maps:get(imsi, Res)),
    ?assertEqual(<<"8988001000000000011">>, maps:get(iccid, Res)),
    {ok, Sub} = udr_data:get_subscription_data(Imsi),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    ?assertEqual(<<"8988001000000000011">>, maps:get(<<"iccid">>, Sub)),
    ok.

rejects_double_provision(Config) ->
    Imsi = ?config(imsi, Config),
    Req  = #{imsi => Imsi, msisdn => <<"49170">>, iccid => <<"8988001000000000012">>},
    {ok, _}     = udr_api_mint:provision(Req),
    {ok, Auth1} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual({error, already_provisioned}, udr_api_mint:provision(Req)),
    {ok, Auth2} = udr_data:get_authentication_subscription(Imsi),
    %% The original Ki must be untouched by the rejected re-provision.
    ?assertEqual(maps:get(<<"ki">>, Auth1), maps:get(<<"ki">>, Auth2)),
    ok.

op_not_configured(Config) ->
    Imsi = ?config(imsi, Config),
    application:unset_env(udr_api, op),
    ?assertEqual(
       {error, op_not_configured},
       udr_api_mint:provision(#{imsi   => Imsi,
                                msisdn => <<"49170">>,
                                iccid  => <<"8988001000000000013">>})),
    ok.

op_misconfigured(Config) ->
    Imsi = ?config(imsi, Config),
    application:set_env(udr_api, op, <<1,2,3>>),  %% not 16 bytes
    ?assertEqual(
       {error, op_misconfigured},
       udr_api_mint:provision(#{imsi   => Imsi,
                                msisdn => <<"49170">>,
                                iccid  => <<"8988001000000000015">>})),
    ok.

minted_creds_authenticate(Config) ->
    Imsi = ?config(imsi, Config),
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

opc_matches_derivation(Config) ->
    Imsi = ?config(imsi, Config),
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

honors_amf_override(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, _} = udr_api_mint:provision(#{imsi   => Imsi,
                                       msisdn => <<"49170">>,
                                       iccid  => <<"8988001000000000016">>,
                                       amf    => <<1,2>>}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(<<1,2>>, maps:get(<<"amf">>, Auth)),
    ok.

passes_through_profile(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, _} = udr_api_mint:provision(#{imsi    => Imsi,
                                       msisdn  => <<"49170">>,
                                       iccid   => <<"8988001000000000017">>,
                                       profile => #{<<"apn_config_profile">> => #{<<"x">> => 1}}}),
    {ok, Sub} = udr_data:get_subscription_data(Imsi),
    ?assertEqual(#{<<"x">> => 1}, maps:get(<<"apn_config_profile">>, Sub)),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    ?assertEqual(<<"8988001000000000017">>, maps:get(<<"iccid">>, Sub)),
    ok.

%% A profile exists (e.g. seeded via the JSON PUT path) but no auth_subscription.
%% Minting must preserve the existing operator profile, not clobber it.
preserves_existing_profile(Config) ->
    Imsi = ?config(imsi, Config),
    ok = udr_data:put_subscription_data(
           Imsi, #{<<"apn_config_profile">> => #{<<"a">> => 1},
                   <<"msisdn">> => <<"stale">>}),
    {ok, _} = udr_api_mint:provision(#{imsi   => Imsi,
                                       msisdn => <<"49170">>,
                                       iccid  => <<"8988001000000000018">>}),
    {ok, Sub} = udr_data:get_subscription_data(Imsi),
    %% Pre-existing field preserved; identity fields (msisdn/iccid) refreshed.
    ?assertEqual(#{<<"a">> => 1}, maps:get(<<"apn_config_profile">>, Sub)),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Sub)),
    ?assertEqual(<<"8988001000000000018">>, maps:get(<<"iccid">>, Sub)),
    ok.

%% Minting a TUAK subscriber: 128-bit Ki, TOPc derived from the 32-byte TOP, and
%% the minted credentials produce valid EPS vectors over AIR.
mints_tuak(Config) ->
    Imsi = ?config(imsi, Config),
    {ok, _} = udr_api_mint:provision(#{imsi      => Imsi,
                                       msisdn    => <<"49170">>,
                                       iccid     => <<"8988001000000000023">>,
                                       algorithm => <<"tuak">>}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    Ki  = maps:get(<<"ki">>, Auth),
    OPc = maps:get(<<"opc">>, Auth),
    ?assertEqual(<<"tuak">>, maps:get(<<"algorithm">>, Auth)),
    ?assertEqual(16, byte_size(Ki)),
    ?assertEqual(32, byte_size(OPc)),
    ?assertEqual(udr_crypto:opc(tuak, Ki, ?TOP), OPc),
    %% Minted creds authenticate end-to-end.
    {ok, Ans, []} = udr_hss:handle_air(#{imsi         => Imsi,
                                         visited_plmn => binary:decode_hex(<<"00f110">>),
                                         num_vectors  => 1}),
    [V] = maps:get(vectors, Ans),
    ?assertEqual(16, byte_size(maps:get(autn, V))),
    ?assertEqual(8,  byte_size(maps:get(xres, V))),
    ?assertEqual(32, byte_size(maps:get(kasme, V))),
    ok.

%% TUAK requested but no operator TOP configured -> fail closed.
tuak_top_not_configured(Config) ->
    Imsi = ?config(imsi, Config),
    application:unset_env(udr_api, top),
    ?assertEqual({error, top_not_configured},
                 udr_api_mint:provision(#{imsi      => Imsi,
                                          msisdn    => <<"49170">>,
                                          iccid     => <<"8988001000000000024">>,
                                          algorithm => <<"tuak">>})),
    ok.

rejects_unsupported_algorithm(Config) ->
    Imsi = ?config(imsi, Config),
    ?assertEqual({error, unsupported_algorithm},
                 udr_api_mint:provision(#{imsi      => Imsi,
                                          msisdn    => <<"49170">>,
                                          iccid     => <<"8988001000000000025">>,
                                          algorithm => <<"xtea">>})),
    ok.

rejects_invalid_identity(_Config) ->
    %% Empty IMSI must never become a lock/storage key.
    ?assertEqual({error, invalid_identity},
                 udr_api_mint:provision(#{imsi   => <<>>,
                                          msisdn => <<"49170">>,
                                          iccid  => <<"8988001000000000019">>})),
    %% Non-numeric ICCID of otherwise-plausible length.
    ?assertEqual({error, invalid_identity},
                 udr_api_mint:provision(#{imsi   => <<"001010000000019">>,
                                          msisdn => <<"49170">>,
                                          iccid  => <<"8988abc010000000x19">>})),
    ok.

rejects_missing_keys(_Config) ->
    %% Missing iccid -> structured error, not a function_clause crash.
    ?assertEqual({error, invalid_request},
                 udr_api_mint:provision(#{imsi   => <<"001010000000020">>,
                                          msisdn => <<"49170">>})),
    ok.

rejects_invalid_amf(Config) ->
    Imsi = ?config(imsi, Config),
    ?assertEqual({error, invalid_amf},
                 udr_api_mint:provision(#{imsi   => Imsi,
                                          msisdn => <<"49170">>,
                                          iccid  => <<"8988001000000000021">>,
                                          amf    => <<1,2,3>>})),  %% must be 2 bytes
    ok.

%% No per-call amf and no default_amf configured -> fail closed (no placeholder).
amf_not_configured(Config) ->
    Imsi = ?config(imsi, Config),
    application:unset_env(udr_api, default_amf),
    ?assertEqual({error, amf_not_configured},
                 udr_api_mint:provision(#{imsi   => Imsi,
                                          msisdn => <<"49170">>,
                                          iccid  => <<"8988001000000000022">>})),
    ok.
