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
-module(udr_db).
-moduledoc "Facade for the pluggable document store. Dispatches to the backend module\n"
           "configured via the `{udr_db, backend}` app env (cached in persistent_term).\n"
           "\n"
           "Provides the higher-level primitives `update/3` and `create/3` on top of the\n"
           "11-callback backend contract. See `database.md` §2.3 for full semantics.".

-export([backend/0, get/2, put/3, delete/2, find/2,
         ensure_collection/2, cas_put/4, take/2, find_by/3, fold/4, count/2,
         update/3, create/3, ready/0, await_ready/1]).

-define(PT_KEY, {udr_db, backend}).
-define(MAX_RETRIES, 100).

-doc "Resolve (and cache) the configured backend module. Defaults to `udr_db_mnesia`.\n"
     "Cached in persistent_term on first call, so changing the `{udr_db, backend}`\n"
     "env at runtime requires a node restart to take effect.".
-spec backend() -> module().
backend() ->
    case persistent_term:get(?PT_KEY, undefined) of
        undefined ->
            Mod = application:get_env(udr_db, backend, udr_db_mnesia),
            persistent_term:put(?PT_KEY, Mod),
            Mod;
        Mod ->
            Mod
    end.

-doc "Fetch a document by collection and key. Returns `{ok, Doc, Version}` where\n"
     "`Version` is the CAS token (metadata, never a doc field).".
-spec get(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
get(Coll, Key) -> (backend()):get(Coll, Key).

-doc "Unconditional upsert. Returns `{ok, Version}` with the new version, or\n"
     "`{error, Reason}` if the backend write fails (infrastructure error, §6.1).".
-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, term()}.
put(Coll, Key, Doc) ->
    (backend()):put(Coll, Key, Doc).

-doc "Delete a document by key. Idempotent.".
-spec delete(udr_db_backend:collection(), udr_db_backend:key()) -> ok.
delete(Coll, Key) -> (backend()):delete(Coll, Key).

-doc "Find documents in a collection by field-equality selector.".
-spec find(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, [udr_db_backend:doc()]}.
find(Coll, Selector) -> (backend()):find(Coll, Selector).

-doc "Create the collection and declare indexes. Idempotent.".
-spec ensure_collection(udr_db_backend:collection(), udr_db_backend:coll_opts()) -> ok.
ensure_collection(Coll, Opts) -> (backend()):ensure_collection(Coll, Opts).

-doc "CAS write: succeeds iff stored version == ExpVsn. Returns new version.".
-spec cas_put(udr_db_backend:collection(), udr_db_backend:key(),
              udr_db_backend:version(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, version_conflict} | {error, not_found}.
cas_put(Coll, Key, ExpVsn, Doc) -> (backend()):cas_put(Coll, Key, ExpVsn, Doc).

-doc "Atomic read-and-delete.".
-spec take(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
take(Coll, Key) -> (backend()):take(Coll, Key).

-doc "Guaranteed indexed read. Errors if Index is not declared.".
-spec find_by(udr_db_backend:collection(), udr_db_backend:index(), term()) ->
    {ok, [udr_db_backend:doc()]} | {error, term()}.
find_by(Coll, Index, Value) -> (backend()):find_by(Coll, Index, Value).

-doc "Streaming cursor iteration over matching documents.".
-spec fold(udr_db_backend:collection(), udr_db_backend:selector(),
           fun((udr_db_backend:doc(), Acc) -> Acc), Acc) -> {ok, Acc}.
fold(Coll, Selector, Fun, Acc) -> (backend()):fold(Coll, Selector, Fun, Acc).

-doc "Count of documents matching selector.".
-spec count(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, non_neg_integer()}.
count(Coll, Selector) -> (backend()):count(Coll, Selector).

-doc "Functional CAS update: `get → Fun(Doc) → cas_put`. Bounded retry (default 100).\n"
     "`Fun :: fun((doc()) -> {ok, doc()} | {abort, term()})`. On `{abort, R}` returns\n"
     "`{error, {aborted, R}}` without retry. Retries on `version_conflict`. Returns\n"
     "`{error, max_retries}` when the retry budget is exhausted.".
-spec update(udr_db_backend:collection(), udr_db_backend:key(),
             fun((udr_db_backend:doc()) -> {ok, udr_db_backend:doc()} | {abort, term()})) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} |
    {error, {aborted, term()}} |
    {error, not_found} |
    {error, max_retries} |
    {error, term()}.
update(Coll, Key, Fun) -> update(Coll, Key, Fun, ?MAX_RETRIES).

-spec update(udr_db_backend:collection(), udr_db_backend:key(),
             fun((udr_db_backend:doc()) -> {ok, udr_db_backend:doc()} | {abort, term()}),
             non_neg_integer()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} |
    {error, {aborted, term()}} |
    {error, not_found} |
    {error, max_retries} |
    {error, term()}.
update(_, _, _, 0) ->
    {error, max_retries};
update(Coll, Key, Fun, N) ->
    case (backend()):get(Coll, Key) of
        {error, not_found} ->
            {error, not_found};
        {ok, Doc, Vsn} ->
            case Fun(Doc) of
                {abort, R} ->
                    {error, {aborted, R}};
                {ok, Doc1} ->
                    case (backend()):cas_put(Coll, Key, Vsn, Doc1) of
                        {ok, V2}                  -> {ok, Doc1, V2};
                        {error, version_conflict} -> update(Coll, Key, Fun, N - 1);
                        {error, not_found}        -> {error, not_found};
                        %% Infrastructure failure (e.g. an aborted transaction):
                        %% propagate rather than crashing the caller (§6.1).
                        {error, Reason}           -> {error, Reason}
                    end
            end
    end.

-doc "Insert-if-absent. Returns `{ok, Version}` on success, `{error, exists}` if a\n"
     "document already exists for the key, or `{error, Reason}` if the backend write\n"
     "fails (infrastructure error, §6.1).\n"
     "Note: the race window between `get` and `put` is not locked by this facade.\n"
     "Callers should hold a per-key `udr_cluster:with_entity` lock when strict\n"
     "uniqueness is required.".
-spec create(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, exists} | {error, term()}.
create(Coll, Key, Doc) ->
    case (backend()):get(Coll, Key) of
        {ok, _, _}         -> {error, exists};
        {error, not_found} -> (backend()):put(Coll, Key, Doc)
    end.

-doc "Returns `true` when the backend is ready to serve requests.\n"
     "For the Mnesia backend, performs a non-blocking (0 ms timeout) check that\n"
     "all local tables (minus the schema table) are loaded. For other backends,\n"
     "returns `true` after the child_spec process is running (connection assumed\n"
     "established at start).".
-spec ready() -> boolean().
ready() ->
    case backend() of
        udr_db_mnesia ->
            Tables = mnesia:system_info(local_tables) -- [schema],
            case udr_db_mnesia:wait_ready_timeout(Tables, 0) of
                ok -> true;
                _  -> false
            end;
        _ ->
            true
    end.

-doc "Block until the backend is ready, or until `Timeout` milliseconds elapse.\n"
     "Returns `ok` when ready, `{error, Reason}` on timeout or failure.\n"
     "For the Mnesia backend, waits for all local tables (minus the schema table)\n"
     "to be loaded. Intended for use in application `start/2` callbacks: call\n"
     "after `ensure_collection/2` so listeners are not started until the backend\n"
     "is fully operational (database.md §6.4).".
-spec await_ready(Timeout :: timeout()) -> ok | {error, term()}.
await_ready(Timeout) ->
    case backend() of
        udr_db_mnesia ->
            Tables = mnesia:system_info(local_tables) -- [schema],
            udr_db_mnesia:wait_ready_timeout(Tables, Timeout);
        _ ->
            ok
    end.
