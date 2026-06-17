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
-module(udr_hss_air_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("udr_hss_test.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([air_returns_vectors_and_advances_sqn/1,
         air_unknown_imsi_returns_user_unknown/1,
         air_incomplete_auth_material_returns_auth_data_unavailable/1,
         air_unknown_algorithm_returns_auth_data_unavailable/1,
         air_tuak_returns_vectors/1]).

all() ->
    [air_returns_vectors_and_advances_sqn,
     air_unknown_imsi_returns_user_unknown,
     air_incomplete_auth_material_returns_auth_data_unavailable,
     air_unknown_algorithm_returns_auth_data_unavailable,
     air_tuak_returns_vectors].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    Config.

end_per_suite(_Config) ->
    udr_db_ct:teardown_mnesia(),
    ok.

init_per_testcase(_TestCase, Config) ->
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    Started = ?config(started, Config),
    [ application:stop(A) || A <- lists:reverse(Started) ],
    ok.

provision(Imsi) ->
    ok = udr_data:put_authentication_subscription(Imsi, #{
        <<"ki">>        => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
        <<"opc">>       => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
        <<"algorithm">> => <<"milenage">>,
        <<"amf">>       => binary:decode_hex(<<"b9b9">>),
        <<"sqn">>       => 32}).

air_returns_vectors_and_advances_sqn(_Config) ->
    Imsi = <<"001010000000001">>,
    provision(Imsi),
    {ok, Ans, Effects} = udr_hss:handle_air(#{imsi => Imsi,
                                              visited_plmn => ?VISITED_PLMN_001_01,
                                              num_vectors => 2}),
    ?assertEqual([], Effects),
    Vs = maps:get(vectors, Ans),
    ?assertEqual(2, length(Vs)),
    lists:foreach(fun(V) ->
        ?assertEqual(16, byte_size(maps:get(rand, V))),
        ?assertEqual(8,  byte_size(maps:get(xres, V))),
        ?assertEqual(16, byte_size(maps:get(autn, V))),
        ?assertEqual(32, byte_size(maps:get(kasme, V)))
    end, Vs),
    ?assertEqual(2, length(lists:usort([maps:get(rand, V) || V <- Vs]))),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(34, maps:get(<<"sqn">>, Auth)),
    ok.

air_unknown_imsi_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_air(#{imsi => <<"nope">>,
                                      visited_plmn => ?VISITED_PLMN_001_01,
                                      num_vectors => 1})),
    ok.

air_incomplete_auth_material_returns_auth_data_unavailable(_Config) ->
    Imsi = <<"001010000000010">>,
    %% Stored subscription is missing ki/opc/amf (only an SQN counter present).
    ok = udr_data:put_authentication_subscription(Imsi, #{<<"sqn">> => 0}),
    ?assertEqual({error, authentication_data_unavailable},
                 udr_hss:handle_air(#{imsi => Imsi,
                                      visited_plmn => ?VISITED_PLMN_001_01,
                                      num_vectors => 1})),
    ok.

air_unknown_algorithm_returns_auth_data_unavailable(_Config) ->
    Imsi = <<"001010000000011">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
        <<"ki">>        => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
        <<"opc">>       => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
        <<"algorithm">> => <<"nonesuch">>,
        <<"amf">>       => binary:decode_hex(<<"b9b9">>),
        <<"sqn">>       => 0}),
    ?assertEqual({error, authentication_data_unavailable},
                 udr_hss:handle_air(#{imsi => Imsi,
                                      visited_plmn => ?VISITED_PLMN_001_01,
                                      num_vectors => 1})),
    ok.

air_tuak_returns_vectors(_Config) ->
    Imsi = <<"001010000000020">>,
    %% Seed a TUAK subscriber: 16-byte Ki, 32-byte TOPc (stored in opc field).
    Ki   = binary:decode_hex(<<"abababababababababababababababab">>),
    TOPc = binary:decode_hex(<<"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd">>),
    ok = udr_data:put_authentication_subscription(Imsi, #{
        <<"ki">>        => Ki,
        <<"opc">>       => TOPc,
        <<"algorithm">> => <<"tuak">>,
        <<"amf">>       => binary:decode_hex(<<"b9b9">>),
        <<"sqn">>       => 0}),
    {ok, Ans, Effects} = udr_hss:handle_air(#{imsi => Imsi,
                                              visited_plmn => ?VISITED_PLMN_001_01,
                                              num_vectors => 2}),
    ?assertEqual([], Effects),
    Vs = maps:get(vectors, Ans),
    ?assertEqual(2, length(Vs)),
    lists:foreach(fun(V) ->
        ?assertEqual(16, byte_size(maps:get(rand, V))),
        ?assertEqual(8,  byte_size(maps:get(xres, V))),
        ?assertEqual(16, byte_size(maps:get(autn, V))),
        ?assertEqual(32, byte_size(maps:get(kasme, V)))
    end, Vs),
    ok.
