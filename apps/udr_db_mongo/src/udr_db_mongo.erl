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
-moduledoc "udr_db_backend implementation over comtihon/mongodb-erlang.\n"
           "\n"
           "Storage layout: one Mongo collection per logical collection; `_id` = key\n"
           "(wrapped as a BSON binary via udr_db_mongo_bson); `version` is a top-level\n"
           "integer field kept out of the doc body — stripped on store, re-attached as the\n"
           "version() in get/take return values. The doc map returned to callers carries\n"
           "no `version` field.\n"
           "\n"
           "Binary VALUES in doc fields are wrapped as `{bin,bin,_}` (BSON binary subtype 0)\n"
           "to prevent non-UTF-8 secret corruption (comtihon encodes raw binary() as BSON\n"
           "string). Integers, version, and _id are handled correctly.\n"
           "\n"
           "Op mapping (database.md §3.2):\n"
           "  get         -> findOne\n"
           "  put         -> replaceOne(upsert:true), version: new key→1, existing→old+1\n"
           "                 (implemented via read-current-version then replace in one op;\n"
           "                  we use $set+$inc on upsert by embedding the version logic\n"
           "                  in a command — see put/3 note below)\n"
           "  cas_put     -> updateOne({_id,version}, $set doc + $inc version:1);\n"
           "                 n=0 re-read to split not_found vs version_conflict\n"
           "  delete      -> deleteOne (idempotent)\n"
           "  take        -> findAndModify (remove:true)\n"
           "  find        -> find (selector match)\n"
           "  find_by     -> find (indexed field match); errors on undeclared index\n"
           "  fold        -> find + mc_cursor:foldl\n"
           "  count       -> count command (countDocuments semantics via filter)\n"
           "  ensure_collection -> createIndex per declared index (idempotent)\n"
           "\n"
           "Declared indexes are tracked in persistent_term under {?MODULE, Coll, indexes}\n"
           "so find_by can validate that the index was declared.\n"
           "\n"
           "See database.md §3.2 and §6.1 for contract semantics.".
-behaviour(udr_db_backend).

-export([child_spec/1, ensure_collection/2, get/2, put/3, cas_put/4,
         delete/2, take/2, find/2, find_by/3, fold/4, count/2]).

%% Pure helpers exported for unit tests
-export([to_mongo/2, from_mongo/1, cas_selector/2, version_strip/1]).

%%--------------------------------------------------------------------
%% child_spec
%%--------------------------------------------------------------------

-spec child_spec(map()) -> supervisor:child_spec().
child_spec(Opts) ->
    #{id      => udr_db_mongo_conn,
      start   => {udr_db_mongo_conn, start_link, [Opts]},
      restart => permanent,
      type    => worker}.

%%--------------------------------------------------------------------
%% ensure_collection
%%--------------------------------------------------------------------

-doc "Create indexes for the collection (idempotent). Declared indexes are stored\n"
     "in persistent_term so find_by can validate them at call time.\n"
     "`mc_worker_api:ensure_index/3` requires a `bson:document()` (flat tuple), not a\n"
     "map — the spec uses `bson:document()` which is `{label(), value(), ...}`.".
-spec ensure_collection(udr_db_backend:collection(), udr_db_backend:coll_opts()) -> ok.
ensure_collection(Coll, Opts) ->
    Indexes = maps:get(indexes, Opts, []),
    CollBin = coll(Coll),
    Conn = conn(),
    lists:foreach(
        fun(Field) ->
            %% bson:document() is a flat tuple {K1, V1, K2, V2, ...}, not a map.
            %% The nested key subdocument is also a flat tuple.
            IndexSpec = {<<"key">>, {Field, 1}, <<"name">>, Field},
            ok = mc_worker_api:ensure_index(Conn, CollBin, IndexSpec)
        end,
        Indexes),
    store_declared_indexes(Coll, Indexes),
    ok.

%%--------------------------------------------------------------------
%% get
%%--------------------------------------------------------------------

-doc "findOne by _id; strips version from doc body, returns it as the version() token.".
-spec get(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
get(Coll, Key) ->
    case mc_worker_api:find_one(conn(), coll(Coll), id_selector(Key)) of
        undefined ->
            {error, not_found};
        Raw when is_map(Raw) ->
            {Doc, Vsn} = decode_with_version(Raw),
            {ok, Doc, Vsn}
    end.

%%--------------------------------------------------------------------
%% put
%%--------------------------------------------------------------------

-doc "Unconditional upsert (replaceOne upsert:true). Version semantics:\n"
     "  new key   -> version 1\n"
     "  existing  -> old version + 1\n"
     "Implemented via findAndModify (upsert) with $set + $inc so version is\n"
     "bumped atomically in a single round-trip. For a brand-new doc the $inc\n"
     "starts from 0 (the implicit default) and produces 1; for existing docs\n"
     "it reads the stored version and increments it.".
-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, term()}.
put(Coll, Key, Doc) ->
    Conn = conn(),
    CollBin = coll(Coll),
    %% Strip any caller-supplied version from the doc body (version is metadata).
    CleanDoc = version_strip(Doc),
    %% Encode the doc fields as BSON-safe values.
    EncodedDoc = udr_db_mongo_bson:encode_doc(CleanDoc),
    %% Use findAndModify with upsert:true to atomically bump version.
    %% $set replaces the doc body fields; $inc bumps version (0->1 for new, N->N+1 for existing).
    %% returnNew:true gives us the post-update document so we can read the new version.
    IdVal = udr_db_mongo_bson:encode_value(Key),
    Cmd = #{
        <<"findAndModify">> => CollBin,
        <<"query">>         => #{<<"_id">> => IdVal},
        <<"update">>        => #{<<"$set">> => EncodedDoc, <<"$inc">> => #{<<"version">> => 1}},
        <<"upsert">>        => true,
        <<"new">>           => true
    },
    case mc_worker_api:command(Conn, Cmd) of
        {true, #{<<"value">> := ResultDoc}} when is_map(ResultDoc) ->
            Vsn = maps:get(<<"version">>, ResultDoc, 1),
            {ok, Vsn};
        {true, #{<<"lastErrorObject">> := _, <<"value">> := null}} ->
            %% Should not happen with returnNew:true + upsert but guard anyway
            {ok, 1};
        {false, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% cas_put
%%--------------------------------------------------------------------

-doc "CAS write: updateOne({_id, version}, $set encoded_doc + $inc version:1).\n"
     "If n=0 (no match), re-reads to distinguish not_found from version_conflict.\n"
     "Returns {ok, NewVersion} on success.".
-spec cas_put(udr_db_backend:collection(), udr_db_backend:key(),
              udr_db_backend:version(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, version_conflict} | {error, not_found}.
cas_put(Coll, Key, ExpVsn, Doc) ->
    Conn = conn(),
    CollBin = coll(Coll),
    CleanDoc = version_strip(Doc),
    EncodedDoc = udr_db_mongo_bson:encode_doc(CleanDoc),
    Sel = cas_selector(Key, ExpVsn),
    Update = #{<<"$set">> => EncodedDoc, <<"$inc">> => #{<<"version">> => 1}},
    case mc_worker_api:update(Conn, CollBin, Sel, Update, false, false) of
        {true, #{<<"n">> := N}} when N > 0 ->
            {ok, ExpVsn + 1};
        {true, #{<<"n">> := 0}} ->
            %% No match: re-read to distinguish not_found vs version_conflict
            case mc_worker_api:find_one(Conn, CollBin, id_selector(Key)) of
                undefined -> {error, not_found};
                _Doc      -> {error, version_conflict}
            end;
        {false, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% delete
%%--------------------------------------------------------------------

-doc "deleteOne by _id. Idempotent — missing key returns ok.".
-spec delete(udr_db_backend:collection(), udr_db_backend:key()) -> ok.
delete(Coll, Key) ->
    _ = mc_worker_api:delete_one(conn(), coll(Coll), id_selector(Key)),
    ok.

%%--------------------------------------------------------------------
%% take
%%--------------------------------------------------------------------

-doc "Atomic read-and-delete via findAndModify(remove:true). Returns {ok,Doc,Vsn} or\n"
     "{error, not_found}.".
-spec take(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
take(Coll, Key) ->
    Conn = conn(),
    CollBin = coll(Coll),
    Cmd = #{
        <<"findAndModify">> => CollBin,
        <<"query">>         => id_selector(Key),
        <<"remove">>        => true
    },
    case mc_worker_api:command(Conn, Cmd) of
        {true, #{<<"value">> := null}} ->
            {error, not_found};
        {true, #{<<"value">> := Raw}} when is_map(Raw) ->
            {Doc, Vsn} = decode_with_version(Raw),
            {ok, Doc, Vsn};
        {true, #{<<"value">> := undefined}} ->
            {error, not_found};
        {false, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% find
%%--------------------------------------------------------------------

-doc "Equality-selector query via find. Returns {ok, [doc()]}. Uses an index when\n"
     "the selector hits one, else scans (Mongo planner decides).".
-spec find(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, [udr_db_backend:doc()]} | {error, cursor_error}.
find(Coll, Selector) ->
    EncodedSel = udr_db_mongo_bson:encode_doc(Selector),
    case mc_worker_api:find(conn(), coll(Coll), EncodedSel) of
        {ok, Cursor} ->
            case collect_cursor(Cursor) of
                {error, cursor_error} = Err -> Err;
                Docs -> {ok, [doc_from_raw(D) || D <- Docs]}
            end;
        [] ->
            {ok, []}
    end.

%%--------------------------------------------------------------------
%% find_by
%%--------------------------------------------------------------------

-doc "Guaranteed indexed read. Errors if Index was not declared in ensure_collection.".
-spec find_by(udr_db_backend:collection(), udr_db_backend:index(), term()) ->
    {ok, [udr_db_backend:doc()]} | {error, undeclared_index} | {error, cursor_error}.
find_by(Coll, Index, Value) ->
    case is_declared_index(Coll, Index) of
        false ->
            {error, undeclared_index};
        true ->
            Selector = #{Index => udr_db_mongo_bson:encode_value(Value)},
            case mc_worker_api:find(conn(), coll(Coll), Selector) of
                {ok, Cursor} ->
                    case collect_cursor(Cursor) of
                        {error, cursor_error} = Err -> Err;
                        Docs -> {ok, [doc_from_raw(D) || D <- Docs]}
                    end;
                [] ->
                    {ok, []}
            end
    end.

%%--------------------------------------------------------------------
%% fold
%%--------------------------------------------------------------------

-doc "Streaming cursor iteration via mc_cursor:foldl. Returns {ok, Acc}.".
-spec fold(udr_db_backend:collection(), udr_db_backend:selector(),
           fun((udr_db_backend:doc(), Acc) -> Acc), Acc) -> {ok, Acc}.
fold(Coll, Selector, Fun, Acc0) ->
    EncodedSel = udr_db_mongo_bson:encode_doc(Selector),
    case mc_worker_api:find(conn(), coll(Coll), EncodedSel) of
        {ok, Cursor} ->
            Acc = mc_cursor:foldl(
                fun(Raw, AccIn) ->
                    Doc = doc_from_raw(Raw),
                    Fun(Doc, AccIn)
                end,
                Acc0, Cursor, infinity),
            {ok, Acc};
        [] ->
            {ok, Acc0}
    end.

%%--------------------------------------------------------------------
%% count
%%--------------------------------------------------------------------

-doc "countDocuments equivalent via the count command with a filter selector.\n"
     "`mc_worker_api:count/3` always returns an `integer()`.".
-spec count(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, non_neg_integer()}.
count(Coll, Selector) ->
    EncodedSel = udr_db_mongo_bson:encode_doc(Selector),
    N = mc_worker_api:count(conn(), coll(Coll), EncodedSel),
    {ok, N}.

%%--------------------------------------------------------------------
%% Pure helpers (exported for unit tests)
%%--------------------------------------------------------------------

-doc "Erlang doc -> Mongo doc: wrap binary values, set _id. Strips any caller-supplied\n"
     "version from the doc body (version is metadata, not a doc field).".
-spec to_mongo(udr_db_backend:key(), map()) -> map().
to_mongo(Key, Doc) ->
    CleanDoc = version_strip(Doc),
    Encoded = udr_db_mongo_bson:encode_doc(CleanDoc),
    Encoded#{<<"_id">> => udr_db_mongo_bson:encode_value(Key)}.

-doc "Mongo raw doc -> Erlang doc: unwrap binaries, drop _id, drop version.".
-spec from_mongo(map() | bson:document()) -> map().
from_mongo(Doc) when is_map(Doc) ->
    Decoded = udr_db_mongo_bson:decode_doc(Doc),
    maps:without([<<"_id">>, <<"version">>], Decoded);
from_mongo(Doc) when is_tuple(Doc) ->
    from_mongo(maps:from_list(bson:fields(Doc))).

-doc "The {_id, version} selector for an optimistic-concurrency update.".
-spec cas_selector(udr_db_backend:key(), non_neg_integer()) -> map().
cas_selector(Key, ExpVsn) ->
    #{<<"_id">> => udr_db_mongo_bson:encode_value(Key), <<"version">> => ExpVsn}.

-doc "Remove the '<<\"version\">>' key from a doc map if present.\n"
     "Version is metadata, never a doc field (database.md §2.2).".
-spec version_strip(map()) -> map().
version_strip(Doc) ->
    maps:remove(<<"version">>, Doc).

%%--------------------------------------------------------------------
%% Private helpers
%%--------------------------------------------------------------------

%% Normalise a raw Mongo doc (either a map or a bson:document() tuple returned
%% by mc_cursor:rest/1) to a plain map before decoding.
-spec raw_to_map(map() | tuple()) -> map().
raw_to_map(Raw) when is_map(Raw)   -> Raw;
raw_to_map(Raw) when is_tuple(Raw) -> maps:from_list(bson:fields(Raw)).

%% Decode a raw Mongo doc (map or bson tuple): unwrap BSON binaries, strip _id,
%% extract version.
-spec decode_with_version(map() | tuple()) -> {udr_db_backend:doc(), udr_db_backend:version()}.
decode_with_version(Raw) ->
    Decoded = udr_db_mongo_bson:decode_doc(raw_to_map(Raw)),
    Vsn = maps:get(<<"version">>, Decoded, 0),
    Doc = maps:without([<<"_id">>, <<"version">>], Decoded),
    {Doc, Vsn}.

%% Decode a raw Mongo doc (map or bson tuple) to a user-visible doc (strips _id and version).
-spec doc_from_raw(map() | tuple()) -> udr_db_backend:doc().
doc_from_raw(Raw) ->
    element(1, decode_with_version(Raw)).

%% Collect all docs from a cursor into a list.
%% mc_cursor:rest/1 returns a list of bson:document() tuples (or the atom `error`).
%% Normal end-of-cursor sentinels ({} or empty list) return the accumulated docs.
%% A genuine error sentinel (the atom `error`) is returned as {error, cursor_error}.
-spec collect_cursor(pid()) -> [tuple()] | {error, cursor_error}.
collect_cursor(Cursor) ->
    case mc_cursor:rest(Cursor) of
        Docs when is_list(Docs) -> Docs;
        {}                      -> [];
        error                   -> {error, cursor_error}
    end.

%% Build the _id equality selector (with BSON-wrapped key).
-spec id_selector(udr_db_backend:key()) -> map().
id_selector(Key) ->
    #{<<"_id">> => udr_db_mongo_bson:encode_value(Key)}.

%% Convert a collection atom to its binary Mongo collection name.
-spec coll(udr_db_backend:collection()) -> binary().
coll(Coll) -> atom_to_binary(Coll, utf8).

%% Retrieve the live connection from the cached persistent_term.
-spec conn() -> pid().
conn() -> udr_db_mongo_conn:conn().

%% Store declared indexes for a collection in persistent_term.
-spec store_declared_indexes(udr_db_backend:collection(), [binary()]) -> ok.
store_declared_indexes(Coll, Indexes) ->
    persistent_term:put({?MODULE, Coll, indexes}, Indexes),
    ok.

%% Check whether a given index was declared via ensure_collection.
-spec is_declared_index(udr_db_backend:collection(), binary()) -> boolean().
is_declared_index(Coll, Index) ->
    Declared = persistent_term:get({?MODULE, Coll, indexes}, []),
    lists:member(Index, Declared).
