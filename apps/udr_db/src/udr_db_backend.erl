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
-moduledoc "Behaviour for `udr_db` storage backends: a generic document store with\n"
           "atomic version-CAS updates. Domain semantics live in `udr_data`, not here.".

-type collection() :: atom().
-type key()        :: binary().
-type doc()        :: #{binary() => term()}.
-type selector()   :: #{binary() => term()}.
-type mutation()   :: #{set => #{binary() => term()}, inc => #{binary() => number()}}.

-export_type([collection/0, key/0, doc/0, selector/0, mutation/0]).

-doc "Return the supervisor child spec for the backend's owning process (if any).".
-callback child_spec(Opts :: map()) -> supervisor:child_spec().

-callback get(collection(), key()) -> {ok, doc()} | {error, not_found}.
-callback put(collection(), key(), doc()) -> ok | {error, term()}.
-callback delete(collection(), key()) -> ok | {error, term()}.
-callback find(collection(), selector()) -> {ok, [doc()]} | {error, term()}.
-callback update(collection(), key(), ExpectedVersion :: non_neg_integer(), mutation()) ->
    {ok, doc()} | {error, version_conflict} | {error, not_found} | {error, term()}.
-callback flush() -> ok | {error, term()}.
