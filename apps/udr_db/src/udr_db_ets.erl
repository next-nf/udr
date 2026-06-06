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
-module(udr_db_ets).
-moduledoc "In-memory ETS backend for `udr_db` (dev/test). A gen_server owns the table\n"
           "and serializes writes so version-CAS updates are atomic.".
-behaviour(udr_db_backend).
-behaviour(gen_server).

-export([child_spec/1, start_link/0]).
-export([get/2, put/3, delete/2, find/2, update/4]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TAB, udr_db_ets_tab).

-doc "Child spec so `udr_db_sup` can start the table-owning gen_server.".
-spec child_spec(map()) -> supervisor:child_spec().
child_spec(_Opts) ->
    #{id => ?MODULE, start => {?MODULE, start_link, []}}.

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---- backend API (reads direct, writes via server) ----

-spec get(atom(), binary()) -> {ok, map()} | {error, not_found}.
get(Coll, Key) ->
    case ets:lookup(?TAB, {Coll, Key}) of
        [{_, Doc}] -> {ok, Doc};
        []         -> {error, not_found}
    end.

-spec put(atom(), binary(), map()) -> ok | {error, term()}.
put(Coll, Key, Doc)    -> gen_server:call(?MODULE, {put, Coll, Key, Doc}).

-spec delete(atom(), binary()) -> ok | {error, term()}.
delete(Coll, Key)      -> gen_server:call(?MODULE, {delete, Coll, Key}).

%% Full O(n) table scan; reads directly (not via the server) so it is NOT snapshot-isolated relative to a concurrent update. Fine for dev/test.
-spec find(atom(), map()) -> {ok, [map()]}.
find(Coll, Selector) ->
    Docs = [Doc || {{C, _K}, Doc} <- ets:tab2list(?TAB),
                   C =:= Coll, selector_matches(Selector, Doc)],
    {ok, Docs}.

-spec update(atom(), binary(), non_neg_integer(), map()) ->
    {ok, map()} | {error, version_conflict} | {error, not_found}.
update(Coll, Key, ExpectedVersion, Mutation) ->
    gen_server:call(?MODULE, {update, Coll, Key, ExpectedVersion, Mutation}).

%% ---- gen_server ----

-spec init([]) -> {ok, map()}.
init([]) ->
    ?TAB = ets:new(?TAB, [named_table, set, protected, {read_concurrency, true}]),
    {ok, #{}}.

-spec handle_call(term(), gen_server:from(), map()) -> {reply, term(), map()}.
handle_call({put, Coll, Key, Doc}, _From, St) ->
    true = ets:insert(?TAB, {{Coll, Key}, Doc}),
    {reply, ok, St};
handle_call({delete, Coll, Key}, _From, St) ->
    true = ets:delete(?TAB, {Coll, Key}),
    {reply, ok, St};
handle_call({update, Coll, Key, ExpVsn, Mutation}, _From, St) ->
    Reply =
        case ets:lookup(?TAB, {Coll, Key}) of
            [] ->
                {error, not_found};
            [{_, Doc}] ->
                case maps:get(<<"version">>, Doc, undefined) of
                    ExpVsn ->
                        New = apply_mutation(Doc, Mutation, ExpVsn),
                        true = ets:insert(?TAB, {{Coll, Key}, New}),
                        {ok, New};
                    _Other ->
                        {error, version_conflict}
                end
        end,
    {reply, Reply, St};
handle_call(_Req, _From, St) ->
    {reply, {error, unexpected_call}, St}.

-spec handle_cast(term(), map()) -> {noreply, map()}.
handle_cast(_Msg, St) ->
    {noreply, St}.

%% ---- private helpers ----

%% Equality match of every selector field against the document.
selector_matches(Selector, Doc) ->
    maps:fold(
      fun(K, V, Acc) -> Acc andalso maps:get(K, Doc, '$nomatch') =:= V end,
      true, Selector).

%% Apply `set` (overwrite) then `inc` (numeric add, base 0), then bump version.
%% If a key appears in both `set` and `inc`, `inc` adds to the post-`set` value.
apply_mutation(Doc, Mutation, ExpVsn) ->
    Set  = maps:get(set, Mutation, #{}),
    Inc  = maps:get(inc, Mutation, #{}),
    Doc1 = maps:merge(Doc, Set),
    Doc2 = maps:fold(fun(K, N, D) -> D#{K => maps:get(K, D, 0) + N} end, Doc1, Inc),
    Doc2#{<<"version">> => ExpVsn + 1}.
