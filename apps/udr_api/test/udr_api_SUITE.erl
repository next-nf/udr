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
-module(udr_api_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PORT, 18090).

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([auth_from_json_opc/1, auth_from_json_derives_opc_from_op/1,
         auth_from_json_tuak/1, auth_from_json_tuak_256k/1, auth_from_json_tuak_bad_opc/1,
         listener_up/1, put_creates_subscriber/1, put_without_op_or_opc_400/1,
         put_malformed_json_400/1, put_storage_error_500/1,
         get_delete_subscriber/1, get_unknown_404/1]).

all() ->
    [auth_from_json_opc, auth_from_json_derives_opc_from_op,
     auth_from_json_tuak, auth_from_json_tuak_256k, auth_from_json_tuak_bad_opc,
     listener_up, put_creates_subscriber, put_without_op_or_opc_400,
     put_malformed_json_400, put_storage_error_500,
     get_delete_subscriber, get_unknown_404].

init_per_suite(Config) ->
    %% Load first so these set_env values are not clobbered by the .app file's
    %% {env, ...} defaults (application:load reads those at load time).
    _ = application:load(udr_db),
    _ = application:load(udr_api),
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    application:set_env(udr_api, port, ?PORT),
    {ok, Started} = application:ensure_all_started(udr_api),
    {ok, _} = application:ensure_all_started(inets),
    [{started, Started} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    udr_db_ct:teardown_mnesia(),
    ok.

url(Path) -> "http://127.0.0.1:" ++ integer_to_list(?PORT) ++ Path.

req(get, Path, _) ->
    httpc:request(get, {url(Path), []}, [], [{body_format, binary}]);
req(delete, Path, _) ->
    httpc:request(delete, {url(Path), []}, [], [{body_format, binary}]);
req(put, Path, Body) ->
    httpc:request(put, {url(Path), [], "application/json", Body}, [], [{body_format, binary}]).
req(Method, Path) -> req(Method, Path, undefined).

%% --- pure conversion unit tests ---
auth_from_json_opc(_Config) ->
    J = #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
          <<"opc">> => <<"cd63cb71954a9f4e48a5994e37a02baf">>,
          <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>, <<"sqn">> => 5},
    M = udr_api_subscriber:auth_from_json(J),
    ?assertEqual(binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>), maps:get(<<"ki">>, M)),
    ?assertEqual(binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>), maps:get(<<"opc">>, M)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, M)),
    ?assertEqual(5, maps:get(<<"sqn">>, M)),
    ?assertEqual(error, maps:find(<<"op">>, M)),
    ok.

auth_from_json_derives_opc_from_op(_Config) ->
    %% MILENAGE Set 1: opc(Ki, OP) = cd63cb71954a9f4e48a5994e37a02baf
    J = #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
          <<"op">> => <<"cdc202d5123e20f62b6d676ac72cb318">>,
          <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>},
    M = udr_api_subscriber:auth_from_json(J),
    ?assertEqual(binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>), maps:get(<<"opc">>, M)),
    ?assertEqual(0, maps:get(<<"sqn">>, M)),
    ok.

%% TUAK: K may be 16 or 32 bytes; opc holds the 32-byte TOPc.
auth_from_json_tuak(_Config) ->
    J = #{<<"ki">> => <<"abababababababababababababababab">>,
          <<"opc">> => <<"bd04d9530e87513c5d837ac2ad954623a8e2330c115305a73eb45d1f40cccbff">>,
          <<"algorithm">> => <<"tuak">>, <<"amf">> => <<"ffff">>, <<"sqn">> => 0},
    M = udr_api_subscriber:auth_from_json(J),
    ?assertEqual(<<"tuak">>, maps:get(<<"algorithm">>, M)),
    ?assertEqual(16, byte_size(maps:get(<<"ki">>, M))),
    ?assertEqual(32, byte_size(maps:get(<<"opc">>, M))),
    ok.

auth_from_json_tuak_256k(_Config) ->
    J = #{<<"ki">> => <<"1574ca56881d05c189c82880f789c9cd4244955f4426aa2b69c29f15770e5aa5">>,
          <<"opc">> => <<"3c6052e41532a28a47aa3cbb89f223e8f3aaa976aecd48bc3e7d6165a55eff62">>,
          <<"algorithm">> => <<"tuak">>, <<"amf">> => <<"297d">>, <<"sqn">> => 0},
    M = udr_api_subscriber:auth_from_json(J),
    ?assertEqual(32, byte_size(maps:get(<<"ki">>, M))),
    ?assertEqual(32, byte_size(maps:get(<<"opc">>, M))),
    ok.

auth_from_json_tuak_bad_opc(_Config) ->
    %% TUAK requires a 32-byte TOPc; a 16-byte opc must be rejected (badarg -> 400).
    J = #{<<"ki">> => <<"abababababababababababababababab">>,
          <<"opc">> => <<"cd63cb71954a9f4e48a5994e37a02baf">>,
          <<"algorithm">> => <<"tuak">>, <<"amf">> => <<"ffff">>, <<"sqn">> => 0},
    ?assertError(badarg, udr_api_subscriber:auth_from_json(J)),
    ok.

%% --- HTTP listener tests ---
listener_up(_Config) ->
    {ok, {{_, Status, _}, _Hdrs, _Body}} = req(get, "/provision/v1/subscribers/nobody"),
    ?assert(is_integer(Status)),
    ok.

%% --- HTTP PUT round-trip ---
put_creates_subscriber(_Config) ->
    Imsi = <<"001010000000001">>,
    Body = udr_api_json:encode(#{
        <<"auth">> => #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
                        <<"op">> => <<"cdc202d5123e20f62b6d676ac72cb318">>,
                        <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>,
                        <<"sqn">> => 0},
        <<"profile">> => #{<<"msisdn">> => <<"49170">>,
                           <<"apn_config_profile">> => #{<<"context_id">> => 1}}}),
    {ok, {{_, 201, _}, _, _}} =
        req(put, "/provision/v1/subscribers/" ++ binary_to_list(Imsi), Body),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
                 maps:get(<<"opc">>, Auth)),
    {ok, Prof} = udr_data:get_subscription_data(Imsi),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Prof)),
    ok.

put_without_op_or_opc_400(_Config) ->
    Body = udr_api_json:encode(#{<<"auth">> => #{<<"ki">> => <<"00">>,
                                                       <<"algorithm">> => <<"milenage">>,
                                                       <<"amf">> => <<"b9b9">>}}),
    {ok, {{_, 400, _}, _, _}} = req(put, "/provision/v1/subscribers/x", Body),
    ok.

put_malformed_json_400(_Config) ->
    {ok, {{_, 400, _}, _, _}} =
        req(put, "/provision/v1/subscribers/x", <<"{not valid json">>),
    ok.

%% A backend write failure on PUT must surface as 500 ("storage error"), not 400.
%% Before the fix, the put_* {ok,_V}= match crashed and the handler's catch-all
%% reported it as a 400 "invalid request body". Force writes to fail to confirm 500.
put_storage_error_500(_Config) ->
    Restore = persistent_term:get({udr_db, backend}, udr_db_mnesia),
    persistent_term:put({udr_db, backend}, udr_db_failing_backend),
    try
        Imsi = <<"001010000000009">>,
        Body = udr_api_json:encode(#{
            <<"auth">> => #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
                            <<"opc">> => <<"cd63cb71954a9f4e48a5994e37a02baf">>,
                            <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>,
                            <<"sqn">> => 0}}),
        {ok, {{_, 500, _}, _, _}} =
            req(put, "/provision/v1/subscribers/" ++ binary_to_list(Imsi), Body)
    after
        persistent_term:put({udr_db, backend}, Restore)
    end,
    ok.

get_delete_subscriber(_Config) ->
    Imsi = <<"001010000000002">>,
    Path = "/provision/v1/subscribers/" ++ binary_to_list(Imsi),
    Body = udr_api_json:encode(#{
        <<"auth">> => #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
                        <<"opc">> => <<"cd63cb71954a9f4e48a5994e37a02baf">>,
                        <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>,
                        <<"sqn">> => 0},
        <<"profile">> => #{<<"msisdn">> => <<"49170">>}}),
    {ok, {{_, 201, _}, _, _}} = req(put, Path, Body),
    {ok, {{_, 200, _}, _, GetBody}} = req(get, Path),
    View = udr_api_json:decode(GetBody),
    #{<<"auth">> := AuthView} = View,
    ?assertEqual(error, maps:find(<<"ki">>, AuthView)),
    ?assertEqual(error, maps:find(<<"opc">>, AuthView)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, AuthView)),
    {ok, {{_, 204, _}, _, _}} = req(delete, Path),
    {ok, {{_, 404, _}, _, _}} = req(get, Path),
    ok.

get_unknown_404(_Config) ->
    {ok, {{_, 404, _}, _, _}} = req(get, "/provision/v1/subscribers/ghost"),
    ok.
