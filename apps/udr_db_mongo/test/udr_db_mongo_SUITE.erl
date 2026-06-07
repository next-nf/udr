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
-module(udr_db_mongo_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([to_mongo_sets_id_and_wraps/1, from_mongo_unwraps_and_strips_id/1,
         mutation_to_update_bumps_version_and_wraps_set/1,
         mutation_to_update_no_set/1, cas_selector/1]).

all() ->
    [to_mongo_sets_id_and_wraps, from_mongo_unwraps_and_strips_id,
     mutation_to_update_bumps_version_and_wraps_set,
     mutation_to_update_no_set, cas_selector].

to_mongo_sets_id_and_wraps(_Config) ->
    M = udr_db_mongo:to_mongo(<<"001010000000001">>, #{<<"ki">> => <<1,2>>, <<"version">> => 1}),
    ?assertEqual({bin, bin, <<"001010000000001">>}, maps:get(<<"_id">>, M)),
    ?assertEqual({bin, bin, <<1,2>>}, maps:get(<<"ki">>, M)),
    ?assertEqual(1, maps:get(<<"version">>, M)),
    ok.

from_mongo_unwraps_and_strips_id(_Config) ->
    Stored = #{<<"_id">> => {bin, bin, <<"k">>}, <<"ki">> => {bin, bin, <<9>>}, <<"version">> => 2},
    ?assertEqual(#{<<"ki">> => <<9>>, <<"version">> => 2},
                 udr_db_mongo:from_mongo(Stored)),
    ok.

mutation_to_update_bumps_version_and_wraps_set(_Config) ->
    Cmd = udr_db_mongo:mutation_to_update(#{set => #{<<"s">> => <<"b">>}, inc => #{<<"sqn">> => 5}}),
    ?assertEqual(#{<<"s">> => {bin, bin, <<"b">>}}, maps:get(<<"$set">>, Cmd)),
    ?assertEqual(#{<<"sqn">> => 5, <<"version">> => 1}, maps:get(<<"$inc">>, Cmd)),
    ok.

mutation_to_update_no_set(_Config) ->
    Cmd = udr_db_mongo:mutation_to_update(#{inc => #{<<"sqn">> => 1}}),
    ?assertEqual(error, maps:find(<<"$set">>, Cmd)),
    ?assertEqual(#{<<"sqn">> => 1, <<"version">> => 1}, maps:get(<<"$inc">>, Cmd)),
    ok.

cas_selector(_Config) ->
    ?assertEqual(#{<<"_id">> => {bin, bin, <<"k">>}, <<"version">> => 3},
                 udr_db_mongo:cas_selector(<<"k">>, 3)),
    ok.
