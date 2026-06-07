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
-module(udr_db_mongo_bson_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([encode_wraps_binaries/1, encode_recurses_nested_and_lists/1,
         roundtrip/1, decode_unwraps/1]).

all() ->
    [encode_wraps_binaries, encode_recurses_nested_and_lists,
     roundtrip, decode_unwraps].

encode_wraps_binaries(_Config) ->
    In  = #{<<"ki">> => <<1,2,255>>, <<"version">> => 1, <<"algo">> => <<"milenage">>},
    Out = udr_db_mongo_bson:encode_doc(In),
    ?assertEqual({bin, bin, <<1,2,255>>}, maps:get(<<"ki">>, Out)),
    ?assertEqual({bin, bin, <<"milenage">>}, maps:get(<<"algo">>, Out)),
    ?assertEqual(1, maps:get(<<"version">>, Out)),
    ok.

encode_recurses_nested_and_lists(_Config) ->
    In  = #{<<"n">> => #{<<"a">> => <<5>>}, <<"l">> => [<<9>>, 2, #{<<"b">> => <<7>>}]},
    Out = udr_db_mongo_bson:encode_doc(In),
    ?assertEqual({bin, bin, <<5>>}, maps:get(<<"a">>, maps:get(<<"n">>, Out))),
    ?assertEqual([{bin, bin, <<9>>}, 2, #{<<"b">> => {bin, bin, <<7>>}}], maps:get(<<"l">>, Out)),
    ok.

roundtrip(_Config) ->
    D = #{<<"ki">> => <<0,255,16,32>>, <<"version">> => 3, <<"sqn">> => 42,
          <<"nested">> => #{<<"opc">> => <<1,2,3,4>>}, <<"list">> => [<<"x">>, 1]},
    ?assertEqual(D, udr_db_mongo_bson:decode_doc(udr_db_mongo_bson:encode_doc(D))),
    ok.

decode_unwraps(_Config) ->
    Stored = #{<<"ki">> => {bin, bin, <<9,9>>}, <<"version">> => 2},
    ?assertEqual(#{<<"ki">> => <<9,9>>, <<"version">> => 2},
                 udr_db_mongo_bson:decode_doc(Stored)),
    ok.
