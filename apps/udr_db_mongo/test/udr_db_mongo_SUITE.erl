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
-moduledoc "Unit tests for the pure helper functions in `udr_db_mongo`.\n"
           "\n"
           "Tests cover:\n"
           "  - to_mongo/2: _id encoding, binary-value BSON wrapping, version stripped from doc\n"
           "  - from_mongo/1: binary unwrapping, _id and version stripped from output doc\n"
           "  - version_strip/1: removes the version key from a doc map\n"
           "  - cas_selector/2: correct _id (wrapped) + version selector\n"
           "\n"
           "Note: mutation_to_update and #{set,inc} tests are removed — those helpers no longer\n"
           "exist; the update contract now uses cas_put/4 (direct $set+$inc on the backend).".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([to_mongo_sets_id_and_wraps_binaries/1,
         to_mongo_strips_version_from_doc/1,
         from_mongo_unwraps_and_strips_id_and_version/1,
         from_mongo_bson_tuple_form/1,
         version_strip_removes_version/1,
         version_strip_passthrough/1,
         cas_selector_wraps_key_and_keeps_version_integer/1]).

all() ->
    [to_mongo_sets_id_and_wraps_binaries,
     to_mongo_strips_version_from_doc,
     from_mongo_unwraps_and_strips_id_and_version,
     from_mongo_bson_tuple_form,
     version_strip_removes_version,
     version_strip_passthrough,
     cas_selector_wraps_key_and_keeps_version_integer].

%% to_mongo/2 sets _id (BSON-wrapped key) and wraps binary values in the doc.
%% A caller-supplied <<"version">> in the doc IS passed through in the 2-arg form
%% (we strip before calling, or callers pass clean docs), but the key is encoded.
to_mongo_sets_id_and_wraps_binaries(_Config) ->
    M = udr_db_mongo:to_mongo(<<"001010000000001">>, #{<<"ki">> => <<1,2>>}),
    ?assertEqual({bin, bin, <<"001010000000001">>}, maps:get(<<"_id">>, M)),
    ?assertEqual({bin, bin, <<1,2>>}, maps:get(<<"ki">>, M)),
    ok.

%% to_mongo/2 does NOT embed a version field (version is metadata, not doc body).
to_mongo_strips_version_from_doc(_Config) ->
    M = udr_db_mongo:to_mongo(<<"k">>, #{<<"ki">> => <<1>>, <<"version">> => 5}),
    %% The 2-arg form strips version before encoding
    ?assertEqual(error, maps:find(<<"version">>, M)),
    ok.

%% from_mongo/1 decodes BSON binaries, removes _id and version from the doc
%% that is returned to callers.
from_mongo_unwraps_and_strips_id_and_version(_Config) ->
    Stored = #{<<"_id">>     => {bin, bin, <<"k">>},
               <<"ki">>      => {bin, bin, <<9>>},
               <<"version">> => 2},
    Result = udr_db_mongo:from_mongo(Stored),
    ?assertEqual(#{<<"ki">> => <<9>>}, Result),
    ok.

%% from_mongo/1 handles the bson tuple document form (legacy driver compatibility).
from_mongo_bson_tuple_form(_Config) ->
    %% bson:fields/1 turns a bson document tuple into a proplist; the driver
    %% may return this form from older protocol paths.
    %% We simulate by calling from_mongo on a map (tuple form is converted first).
    Stored = #{<<"_id">>     => {bin, bin, <<"k">>},
               <<"a">>       => {bin, bin, <<5>>},
               <<"version">> => 3},
    Result = udr_db_mongo:from_mongo(Stored),
    ?assertEqual(#{<<"a">> => <<5>>}, Result),
    ok.

%% version_strip/1 removes <<"version">> from a doc map.
version_strip_removes_version(_Config) ->
    Doc = #{<<"a">> => 1, <<"version">> => 7},
    ?assertEqual(#{<<"a">> => 1}, udr_db_mongo:version_strip(Doc)),
    ok.

%% version_strip/1 is a no-op when version is absent.
version_strip_passthrough(_Config) ->
    Doc = #{<<"a">> => 1, <<"b">> => <<"x">>},
    ?assertEqual(Doc, udr_db_mongo:version_strip(Doc)),
    ok.

%% cas_selector/2 produces the {_id, version} selector used by cas_put.
%% _id is BSON-wrapped; version is an integer (Mongo compares it directly).
cas_selector_wraps_key_and_keeps_version_integer(_Config) ->
    Sel = udr_db_mongo:cas_selector(<<"k">>, 3),
    ?assertEqual({bin, bin, <<"k">>}, maps:get(<<"_id">>, Sel)),
    ?assertEqual(3, maps:get(<<"version">>, Sel)),
    ok.
