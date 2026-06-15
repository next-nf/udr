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
-module(udr_db_mongo).
-moduledoc "udr_db_backend implementation over comtihon/mongodb-erlang. Every document and\n"
           "selector is run through udr_db_mongo_bson (binary->{bin,bin,_}); version stays an\n"
           "integer for numeric CAS. Conflicts are detected via the update match count (n).".
-behaviour(udr_db_backend).

-export([child_spec/1, get/2, put/3, delete/2, find/2, update/4, flush/0]).
-export([to_mongo/2, from_mongo/1, mutation_to_update/1, cas_selector/2]).

%% The collections udr_data manages; flush empties each. Keep in sync with the
%% collection atoms used by udr_data (auth_subscription / subscription_data /
%% access_registration).
-define(COLLECTIONS, [<<"auth_subscription">>, <<"subscription_data">>,
                      <<"access_registration">>]).

-spec child_spec(map()) -> supervisor:child_spec().
child_spec(Opts) ->
    #{id => udr_db_mongo_conn,
      start => {udr_db_mongo_conn, start_link, [Opts]}}.

-spec get(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc()} | {error, not_found}.
get(Coll, Key) ->
    case mc_worker_api:find_one(conn(), coll(Coll), id_selector(Key)) of
        undefined            -> {error, not_found};
        Doc when is_map(Doc) -> {ok, from_mongo(Doc)}
    end.

-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    ok | {error, term()}.
put(Coll, Key, Doc) ->
    case mc_worker_api:update(conn(), coll(Coll), id_selector(Key), to_mongo(Key, Doc), true, false) of
        {true, _} -> ok;
        Other     -> {error, Other}
    end.

-spec delete(udr_db_backend:collection(), udr_db_backend:key()) -> ok | {error, term()}.
delete(Coll, Key) ->
    case mc_worker_api:delete(conn(), coll(Coll), id_selector(Key)) of
        {true, _} -> ok;
        Other     -> {error, Other}
    end.

-spec find(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, [udr_db_backend:doc()]} | {error, term()}.
find(Coll, Selector) ->
    case mc_worker_api:find(conn(), coll(Coll), udr_db_mongo_bson:encode_doc(Selector)) of
        {ok, Cursor} ->
            case mc_cursor:rest(Cursor) of
                Docs when is_list(Docs) -> {ok, [from_mongo(D) || D <- Docs]};
                error                   -> {error, cursor_error}
            end;
        [] ->
            {ok, []}
    end.

-spec update(udr_db_backend:collection(), udr_db_backend:key(), non_neg_integer(),
             udr_db_backend:mutation()) ->
    {ok, udr_db_backend:doc()} | {error, version_conflict} | {error, not_found} | {error, term()}.
update(Coll, Key, ExpVsn, Mutation) ->
    Sel = cas_selector(Key, ExpVsn),
    case mc_worker_api:update(conn(), coll(Coll), Sel, mutation_to_update(Mutation), false, false) of
        {true, #{<<"n">> := 0}} ->
            case mc_worker_api:find_one(conn(), coll(Coll), id_selector(Key)) of
                undefined -> {error, not_found};
                _         -> {error, version_conflict}
            end;
        {true, #{<<"n">> := _N}} ->
            get(Coll, Key);
        Other ->
            {error, Other}
    end.

-doc "Delete all documents from every managed collection. Test/admin use only;\n"
     "callers gate this through udr_db:flush/0.".
-spec flush() -> ok.
flush() ->
    lists:foreach(fun(Coll) -> _ = mc_worker_api:delete(conn(), Coll, #{}) end,
                  ?COLLECTIONS),
    ok.

%% --- pure helpers (unit-tested) ---
-doc "Erlang doc -> Mongo doc: wrap binary values, set _id to the (wrapped) Key.".
-spec to_mongo(udr_db_backend:key(), map()) -> map().
to_mongo(Key, Doc) ->
    (udr_db_mongo_bson:encode_doc(Doc))#{<<"_id">> => udr_db_mongo_bson:encode_value(Key)}.

-doc "Mongo doc -> Erlang doc: unwrap binaries, drop the _id. The driver yields\n"
     "maps at runtime; the bson:document() tuple form is converted first so the\n"
     "cursor's [bson:document()] spec type-checks.".
-spec from_mongo(map() | bson:document()) -> map().
from_mongo(Doc) when is_map(Doc) ->
    maps:remove(<<"_id">>, udr_db_mongo_bson:decode_doc(Doc));
from_mongo(Doc) when is_tuple(Doc) ->
    from_mongo(maps:from_list(bson:fields(Doc))).

-doc "Build the CAS update command: $set (wrapped) + $inc with version+1.".
-spec mutation_to_update(udr_db_backend:mutation()) -> map().
mutation_to_update(Mutation) ->
    Set = maps:get(set, Mutation, #{}),
    Inc = maps:get(inc, Mutation, #{}),
    Base = #{<<"$inc">> => Inc#{<<"version">> => 1}},
    case map_size(Set) of
        0 -> Base;
        _ -> Base#{<<"$set">> => udr_db_mongo_bson:encode_doc(Set)}
    end.

-doc "The {_id, version} selector for an optimistic-concurrency update.".
-spec cas_selector(udr_db_backend:key(), non_neg_integer()) -> map().
cas_selector(Key, ExpVsn) ->
    #{<<"_id">> => udr_db_mongo_bson:encode_value(Key), <<"version">> => ExpVsn}.

%% --- internals ---
id_selector(Key) -> #{<<"_id">> => udr_db_mongo_bson:encode_value(Key)}.
coll(Coll)       -> atom_to_binary(Coll, utf8).
conn()           -> udr_db_mongo_conn:conn().
