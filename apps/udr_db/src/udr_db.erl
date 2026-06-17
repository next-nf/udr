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
           "configured via the `{udr_db, backend}` app env (cached in persistent_term).".

-export([backend/0, get/2, put/3, delete/2, find/2, update/4, flush/0]).

-define(PT_KEY, {udr_db, backend}).

-doc "Resolve (and cache) the configured backend module. Defaults to `udr_db_ets`.\n"
     "Cached in persistent_term on first call, so changing the `{udr_db, backend}`\n"
     "env at runtime requires a node restart to take effect.".
-spec backend() -> module().
backend() ->
    case persistent_term:get(?PT_KEY, undefined) of
        undefined ->
            Mod = application:get_env(udr_db, backend, udr_db_ets),
            persistent_term:put(?PT_KEY, Mod),
            Mod;
        Mod ->
            Mod
    end.

-doc "Fetch a document by collection and key.".
-spec get(udr_db_backend:collection(), udr_db_backend:key()) ->
    {ok, udr_db_backend:doc()} | {error, not_found}.
get(Coll, Key) -> (backend()):get(Coll, Key).

-doc "Insert or replace a document. Initializes the `version` token to 1 if absent.".
-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    ok | {error, term()}.
put(Coll, Key, Doc) ->
    (backend()):put(Coll, Key, maps:merge(#{<<"version">> => 1}, Doc)).

-doc "Delete a document by key.".
-spec delete(udr_db_backend:collection(), udr_db_backend:key()) -> ok | {error, term()}.
delete(Coll, Key) -> (backend()):delete(Coll, Key).

-doc "Find documents in a collection by field-equality selector.".
-spec find(udr_db_backend:collection(), udr_db_backend:selector()) ->
    {ok, [udr_db_backend:doc()]} | {error, term()}.
find(Coll, Selector) -> (backend()):find(Coll, Selector).

-doc "Atomic compare-and-swap update: apply Mutation iff the stored `version` equals\n"
     "ExpectedVersion, bumping `version` to ExpectedVersion+1. Returns the new document.".
-spec update(udr_db_backend:collection(), udr_db_backend:key(), non_neg_integer(),
             map()) ->
    {ok, udr_db_backend:doc()} | {error, version_conflict} | {error, not_found} | {error, term()}.
update(Coll, Key, ExpectedVersion, Mutation) ->
    (backend()):update(Coll, Key, ExpectedVersion, Mutation).

-doc "Empty the entire store. DESTRUCTIVE and test/admin-only: refuses unless the\n"
     "`{udr_db, allow_flush}` env is explicitly true (default false), so production\n"
     "cannot wipe data by accident.".
-spec flush() -> ok | {error, term()}.
flush() ->
    case application:get_env(udr_db, allow_flush, false) of
        true  -> (backend()):flush();
        false -> {error, flush_not_allowed}
    end.
