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
-module(udr_api_mint_h_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2,
         end_per_testcase/2]).
-export([mint_201/1, mint_conflict_409/1, missing_iccid_400/1,
         bad_amf_400/1, op_not_configured_500/1, put_unchanged/1,
         non_hex_amf_400/1]).

-define(PORT, 8099).
-define(OP, binary:decode_hex(<<"000102030405060708090a0b0c0d0e0f">>)).

all() ->
    [mint_201, mint_conflict_409, missing_iccid_400, bad_amf_400,
     op_not_configured_500, put_unchanged, non_hex_amf_400].

init_per_suite(Config) ->
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
    [application:stop(A) || A <- lists:reverse(?config(started, Config))],
    udr_db_ct:teardown_mnesia(),
    ok.

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_api, op, ?OP),
    application:set_env(udr_api, default_amf, binary:decode_hex(<<"b9b9">>)),
    Config.

end_per_testcase(_TestCase, _Config) ->
    application:set_env(udr_api, op, ?OP),
    application:set_env(udr_api, default_amf, binary:decode_hex(<<"b9b9">>)),
    ok.

url(Path) -> "http://127.0.0.1:" ++ integer_to_list(?PORT) ++ Path.

post(Path, Body) ->
    httpc:request(post, {url(Path), [], "application/json", Body}, [],
                  [{body_format, binary}]).

mint_path(Imsi) -> "/provision/v1/subscribers/" ++ binary_to_list(Imsi) ++ "/mint".

mint_201(_Config) ->
    Imsi = <<"001010000000201">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>,
                                 <<"iccid">>  => <<"8988001000000000201">>}),
    {ok, {{_, 201, _}, _Hdrs, Resp}} = post(mint_path(Imsi), Body),
    Decoded = udr_api_json:decode(Resp),
    ?assertEqual(Imsi, maps:get(<<"imsi">>, Decoded)),
    ?assertEqual(<<"minted">>, maps:get(<<"status">>, Decoded)),
    ok.

mint_conflict_409(_Config) ->
    Imsi = <<"001010000000202">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>,
                                 <<"iccid">>  => <<"8988001000000000202">>}),
    {ok, {{_, 201, _}, _, _}} = post(mint_path(Imsi), Body),
    {ok, {{_, 409, _}, _, _}} = post(mint_path(Imsi), Body),
    ok.

missing_iccid_400(_Config) ->
    Imsi = <<"001010000000203">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>}),
    {ok, {{_, 400, _}, _, _}} = post(mint_path(Imsi), Body),
    ok.

bad_amf_400(_Config) ->
    Imsi = <<"001010000000204">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>,
                                 <<"iccid">>  => <<"8988001000000000204">>,
                                 <<"amf">>    => <<"b9b9b9">>}),
    {ok, {{_, 400, _}, _, _}} = post(mint_path(Imsi), Body),
    ok.

op_not_configured_500(_Config) ->
    application:unset_env(udr_api, op),
    Imsi = <<"001010000000205">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>,
                                 <<"iccid">>  => <<"8988001000000000205">>}),
    {ok, {{_, 500, _}, _, _}} = post(mint_path(Imsi), Body),
    ok.

non_hex_amf_400(_Config) ->
    Imsi = <<"001010000000207">>,
    Body = udr_api_json:encode(#{<<"msisdn">> => <<"49170">>,
                                 <<"iccid">>  => <<"8988001000000000207">>,
                                 <<"amf">>    => <<"zzzz">>}),  %% not hex -> decode throws -> 400
    {ok, {{_, 400, _}, _, _}} = post(mint_path(Imsi), Body),
    ok.

put_unchanged(_Config) ->
    Imsi = <<"001010000000206">>,
    Auth = #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
             <<"op">> => <<"000102030405060708090a0b0c0d0e0f">>,
             <<"amf">> => <<"b9b9">>},
    Body = udr_api_json:encode(#{<<"auth">> => Auth}),
    {ok, {{_, 201, _}, _, _}} =
        httpc:request(put, {url("/provision/v1/subscribers/" ++ binary_to_list(Imsi)),
                            [], "application/json", Body}, [], [{body_format, binary}]),
    ok.
