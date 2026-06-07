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
-module(udr_provision_e2e_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PORT, 18091).

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([provision_then_air/1]).

all() -> [provision_then_air].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    %% load before set_env so the .app default port doesn't clobber the test port
    application:load(udr_provision),
    application:set_env(udr_provision, port, ?PORT),
    {ok, S1} = application:ensure_all_started(udr_hss),
    {ok, S2} = application:ensure_all_started(udr_provision),
    {ok, _}  = application:ensure_all_started(inets),
    [{started, lists:usort(S1 ++ S2)} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    ok.

provision_then_air(_Config) ->
    Imsi = <<"001010000000001">>,
    Path = "http://127.0.0.1:" ++ integer_to_list(?PORT)
           ++ "/provision/v1/subscribers/" ++ binary_to_list(Imsi),
    Body = iolist_to_binary(json:encode(#{
        <<"auth">> => #{<<"ki">> => <<"465b5ce8b199b49faa5f0a2ee238a6bc">>,
                        <<"op">> => <<"cdc202d5123e20f62b6d676ac72cb318">>,
                        <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"b9b9">>,
                        <<"sqn">> => 0},
        <<"profile">> => #{<<"apn_config_profile">> => #{<<"context_id">> => 1}}})),
    {ok, {{_, 201, _}, _, _}} =
        httpc:request(put, {Path, [], "application/json", Body}, [], [{body_format, binary}]),
    {ok, #{vectors := Vs}, []} =
        udr_hss:handle_air(#{imsi => Imsi,
                             visited_plmn => binary:decode_hex(<<"00f110">>),
                             num_vectors => 1}),
    ?assertEqual(1, length(Vs)),
    ok.
