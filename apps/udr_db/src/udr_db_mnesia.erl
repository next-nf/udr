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
-module(udr_db_mnesia).
-moduledoc "Mnesia backend for `udr_db`. Implements the 11-callback contract via a\n"
           "generic envelope with promoted index columns (database.md §3.1).\n"
           "\n"
           "Table layout: `attributes = [key | AtomIdxFields] ++ [version, doc]`.\n"
           "Binary index names from `coll_opts()` are converted to atoms for Mnesia\n"
           "attribute names; the mapping is stored in `persistent_term` keyed by\n"
           "`{udr_db_mnesia, Coll, idx}` (node-global, txn-safe) so `find_by` can resolve names to positions.\n"
           "\n"
           "Read ops (`get`, `find`, `find_by`, `count`) are dirty/lock-free (P7).\n"
           "`cas_put` and `take` use `mnesia:transaction`. `fold` uses `async_dirty`.".
-behaviour(udr_db_backend).
-behaviour(gen_server).

%% Public API
-export([child_spec/1, start_link/1, wait_ready/1, wait_ready_timeout/2]).

%% udr_db_backend callbacks
-export([ensure_collection/2, get/2, put/3, cas_put/4, delete/2,
         take/2, find/2, find_by/3, fold/4, count/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%%--------------------------------------------------------------------
%% child_spec / start_link
%%--------------------------------------------------------------------

-doc "Child spec for `udr_db_sup`.".
-spec child_spec(map()) -> supervisor:child_spec().
child_spec(Opts) ->
    #{id      => ?MODULE,
      start   => {?MODULE, start_link, [Opts]},
      restart => permanent,
      type    => worker}.

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

-doc "Wait until all listed tables (or a single table) are ready (loaded into Mnesia).\n"
     "Uses a default timeout of 5 000 ms. Used as the readiness gate\n"
     "(database.md §6.4; Task 8 calls this).".
-spec wait_ready([atom()] | atom()) -> ok | {error, term()}.
wait_ready(Colls) when is_list(Colls) ->
    wait_ready_timeout(Colls, 5000);
wait_ready(Coll) when is_atom(Coll) ->
    wait_ready([Coll]).

-doc "Wait until all listed tables are ready with an explicit timeout.\n"
     "Returns `ok` when all tables are loaded, `{error, Reason}` on timeout or failure.\n"
     "Called by `udr_db:await_ready/1` (database.md §6.4).".
-spec wait_ready_timeout([atom()], timeout()) -> ok | {error, term()}.
wait_ready_timeout(Colls, Timeout) ->
    case mnesia:wait_for_tables(Colls, Timeout) of
        ok              -> ok;
        {timeout, Tabs} -> {error, {timeout, Tabs}};
        {error, Reason} -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

-spec init(map()) -> {ok, map()}.
init(_Opts) ->
    {ok, #{}}.

-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()}.
handle_call(_Req, _From, St) ->
    {reply, {error, unexpected_call}, St}.

-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_Msg, St) ->
    {noreply, St}.

-spec handle_info(term(), map()) -> {noreply, map()}.
handle_info(_Info, St) ->
    {noreply, St}.

-spec terminate(term(), map()) -> ok.
terminate(_Reason, _St) ->
    ok.

%%--------------------------------------------------------------------
%% ensure_collection
%%--------------------------------------------------------------------

-doc "Create the Mnesia table for `Coll` with declared indexes. Idempotent.".
-spec ensure_collection(udr_db_backend:collection(), udr_db_backend:coll_opts()) -> ok.
ensure_collection(Coll, Opts) ->
    BinIdx   = maps:get(indexes, Opts, []),
    Storage  = maps:get(storage, Opts, ram_copies),
    %% Mnesia attributes must be atoms; convert binary index names.
    AtomIdx  = [binary_to_atom(B) || B <- BinIdx],
    Attrs    = [key | AtomIdx] ++ [version, doc],
    case mnesia:create_table(Coll, [{attributes, Attrs},
                                    {Storage, [node()]},
                                    {index, AtomIdx},
                                    {type, set}]) of
        {atomic, ok}                    -> ok;
        {aborted, {already_exists, _}}  -> ok
    end,
    store_meta(Coll, BinIdx, AtomIdx),
    ok.

%%--------------------------------------------------------------------
%% get / put / cas_put / delete / take
%%--------------------------------------------------------------------

-doc "Dirty (lock-free) read. Returns `{ok, Doc, Version}` or `{error, not_found}`.".
-spec get(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
get(Coll, Key) ->
    case mnesia:dirty_read(Coll, Key) of
        [Row] -> {ok, row_doc(Coll, Row), row_version(Coll, Row)};
        []    -> {error, not_found}
    end.

-doc "Unconditional upsert in a transaction. Bumps version by 1; sets to 1 for new keys.".
-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()}.
put(Coll, Key, Doc) ->
    F = fun() ->
        NewVsn = case mnesia:read(Coll, Key, write) of
            [Row] -> row_version(Coll, Row) + 1;
            []    -> 1
        end,
        ok = mnesia:write(make_row(Coll, Key, NewVsn, Doc)),
        NewVsn
    end,
    case mnesia:transaction(F) of
        {atomic, V}  -> {ok, V};
        {aborted, R} -> {error, {aborted, R}}
    end.

-doc "CAS write: succeeds iff stored version == ExpVsn. Returns new version on success.".
-spec cas_put(udr_db_backend:collection(), udr_db_backend:key(),
              udr_db_backend:version(), udr_db_backend:doc()) ->
    {ok, udr_db_backend:version()} | {error, version_conflict} | {error, not_found}.
cas_put(Coll, Key, ExpVsn, Doc) ->
    F = fun() ->
        case mnesia:read(Coll, Key, write) of
            [Row] ->
                case row_version(Coll, Row) of
                    ExpVsn ->
                        NewVsn = ExpVsn + 1,
                        ok = mnesia:write(make_row(Coll, Key, NewVsn, Doc)),
                        {ok, NewVsn};
                    _ ->
                        {error, version_conflict}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, R}     -> {error, {aborted, R}}
    end.

-doc "Idempotent delete (dirty).".
-spec delete(udr_db_backend:collection(), udr_db_backend:key()) -> ok.
delete(Coll, Key) ->
    mnesia:dirty_delete(Coll, Key).

-doc "Atomic read-and-delete in a transaction.".
-spec take(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc(), udr_db_backend:version()} | {error, not_found}.
take(Coll, Key) ->
    F = fun() ->
        case mnesia:read(Coll, Key, write) of
            [Row] ->
                ok = mnesia:delete(Coll, Key, write),
                {ok, row_doc(Coll, Row), row_version(Coll, Row)};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, R}     -> {error, {aborted, R}}
    end.

%%--------------------------------------------------------------------
%% find / find_by / fold / count
%%--------------------------------------------------------------------

-doc "Dirty table scan filtered by selector equality.".
-spec find(udr_db_backend:collection(), udr_db_backend:selector()) -> {ok, [udr_db_backend:doc()]}.
find(Coll, Selector) ->
    Pattern = mnesia:table_info(Coll, wild_pattern),
    Rows    = mnesia:dirty_match_object(Coll, Pattern),
    Docs    = [Doc || Row <- Rows,
               Doc <- [row_doc(Coll, Row)],
               selector_matches(Selector, Doc)],
    {ok, Docs}.

-doc "Guaranteed indexed read via `mnesia:dirty_index_read`. Returns `{error, undeclared_index}`\n"
     "if the index was not declared in `ensure_collection`.".
-spec find_by(udr_db_backend:collection(), udr_db_backend:index(), term()) ->
    {ok, [udr_db_backend:doc()]} | {error, undeclared_index}.
find_by(Coll, BinIndex, Value) ->
    {BinIdxs, AtomIdxs} = get_meta(Coll),
    case find_atom_idx(BinIndex, BinIdxs, AtomIdxs) of
        {ok, AtomIdx} ->
            Rows = mnesia:dirty_index_read(Coll, Value, AtomIdx),
            {ok, [row_doc(Coll, Row) || Row <- Rows]};
        error ->
            {error, undeclared_index}
    end.

-doc "Streaming async-dirty fold over all matching documents.".
-spec fold(udr_db_backend:collection(), udr_db_backend:selector(),
           fun((udr_db_backend:doc(), Acc) -> Acc), Acc) -> {ok, Acc}.
fold(Coll, Selector, Fun, Acc0) ->
    F = fun() ->
        mnesia:foldl(
            fun(Row, Acc) ->
                Doc = row_doc(Coll, Row),
                case selector_matches(Selector, Doc) of
                    true  -> Fun(Doc, Acc);
                    false -> Acc
                end
            end,
            Acc0, Coll)
    end,
    {ok, mnesia:activity(async_dirty, F)}.

-doc "Count of documents matching selector.".
-spec count(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, non_neg_integer()}.
count(Coll, Selector) ->
    {ok, Docs} = find(Coll, Selector),
    {ok, length(Docs)}.

%%--------------------------------------------------------------------
%% Private helpers
%%--------------------------------------------------------------------

%% Store binary-to-atom index mapping for a collection in persistent_term.
%% persistent_term is safe to read from any process including Mnesia txn workers.
-spec store_meta(atom(), [binary()], [atom()]) -> ok.
store_meta(Coll, BinIdx, AtomIdx) ->
    persistent_term:put({?MODULE, Coll, idx}, {BinIdx, AtomIdx}).

%% Retrieve the index mapping for a collection.
%% Returns {BinIdxs, AtomIdxs}. Defaults to empty lists if not found.
-spec get_meta(atom()) -> {[binary()], [atom()]}.
get_meta(Coll) ->
    persistent_term:get({?MODULE, Coll, idx}, {[], []}).

%% Resolve a binary index name to its corresponding atom attribute name.
-spec find_atom_idx(binary(), [binary()], [atom()]) -> {ok, atom()} | error.
find_atom_idx(_, [], []) ->
    error;
find_atom_idx(BinIdx, [BinIdx | _], [AtomIdx | _]) ->
    {ok, AtomIdx};
find_atom_idx(BinIdx, [_ | BinRest], [_ | AtomRest]) ->
    find_atom_idx(BinIdx, BinRest, AtomRest).

%% Build a Mnesia row tuple.
%% Tuple layout: {Coll, Key, AtomIdxVal1, ..., Version, Doc}
%% where AtomIdx fields are in the order declared in ensure_collection.
-spec make_row(atom(), binary(), non_neg_integer(), map()) -> tuple().
make_row(Coll, Key, Version, Doc) ->
    {BinIdx, _AtomIdx} = get_meta(Coll),
    IdxVals = [maps:get(F, Doc, undefined) || F <- BinIdx],
    list_to_tuple([Coll, Key | IdxVals] ++ [Version, Doc]).

%% Extract version from a Mnesia row tuple.
%% Layout: {Coll, Key, Idx1, ..., IdxN, Version, Doc}
%% Version is at position 3 + length(BinIdx) (1-based).
-spec row_version(atom(), tuple()) -> non_neg_integer().
row_version(Coll, Row) ->
    {BinIdx, _} = get_meta(Coll),
    element(3 + length(BinIdx), Row).

%% Extract doc map from a Mnesia row tuple.
%% Doc is at position 4 + length(BinIdx) (1-based).
-spec row_doc(atom(), tuple()) -> map().
row_doc(Coll, Row) ->
    {BinIdx, _} = get_meta(Coll),
    element(4 + length(BinIdx), Row).

%% Equality-match selector against a doc map.
-spec selector_matches(map(), map()) -> boolean().
selector_matches(Selector, Doc) ->
    maps:fold(
        fun(K, V, Acc) -> Acc andalso maps:get(K, Doc, '$nomatch') =:= V end,
        true, Selector).
