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
-module(udr_db_backend).
-moduledoc "Behaviour for `udr_db` storage backends: an 11-callback document store with\n"
           "version-as-metadata CAS. Domain semantics live in `udr_data`, not here.\n"
           "See `database.md` §2 for full contract semantics.".

-type collection() :: atom().
-type key()        :: binary().
-type doc()        :: #{binary() => term()}.
-type version()    :: non_neg_integer().
-type selector()   :: #{binary() => term()}.
-type index()      :: binary().
-type coll_opts()  :: #{indexes => [index()], storage => ram_copies | disc_copies}.

-export_type([collection/0, key/0, doc/0, version/0, selector/0, index/0, coll_opts/0]).

-doc "Return the supervisor child spec for the backend's owning process (if any).".
-callback child_spec(Opts :: map()) -> supervisor:child_spec().

-doc "Create the collection and declare indexes, idempotent.".
-callback ensure_collection(collection(), coll_opts()) -> ok.

-doc "Fetch a document. May use a dirty/lock-free read (P7).".
-callback get(collection(), key()) -> {ok, doc(), version()} | {error, not_found}.

-doc "Unconditional upsert. Returns the new version, or `{error, Reason}` on an\n"
     "infrastructure failure (e.g. an aborted transaction / driver error, §6.1).".
-callback put(collection(), key(), doc()) -> {ok, version()} | {error, term()}.

-doc "Write iff stored version == ExpectedVersion, bump version.".
-callback cas_put(collection(), key(), version(), doc()) ->
    {ok, version()} | {error, version_conflict} | {error, not_found}.

-doc "Delete a document. Idempotent.".
-callback delete(collection(), key()) -> ok.

-doc "Atomic read-and-delete.".
-callback take(collection(), key()) -> {ok, doc(), version()} | {error, not_found}.

-doc "Equality-selector query. Scans if no index covers the selector.".
-callback find(collection(), selector()) -> {ok, [doc()]}.

-doc "Guaranteed indexed read. Errors if Index is not declared.".
-callback find_by(collection(), index(), term()) -> {ok, [doc()]} | {error, term()}.

-doc "Streaming cursor iteration over matching documents.".
-callback fold(collection(), selector(), fun((doc(), Acc) -> Acc), Acc) -> {ok, Acc}.

-doc "Count of documents matching selector.".
-callback count(collection(), selector()) -> {ok, non_neg_integer()}.
