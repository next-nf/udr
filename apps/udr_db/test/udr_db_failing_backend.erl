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
-module(udr_db_failing_backend).
-moduledoc "Test-only `udr_db` backend whose writes always fail. Used to verify that a\n"
           "backend (infrastructure) error propagates through `udr_data` and surfaces as a\n"
           "5xx — never collapsing into a crash that a handler misreports as a 4xx.\n"
           "`get/2` reports `not_found` so create-then-write paths reach the write.\n"
           "Install by overriding the cached backend:\n"
           "`persistent_term:put({udr_db, backend}, udr_db_failing_backend)`.".

%% Only the callbacks exercised by the storage-error tests are implemented; the
%% rest of the 11-callback contract is intentionally absent (never invoked here).
-export([get/2, put/3]).

-spec get(udr_db_backend:collection(), udr_db_backend:key()) -> {error, not_found}.
get(_Coll, _Key) ->
    {error, not_found}.

-spec put(udr_db_backend:collection(), udr_db_backend:key(), udr_db_backend:doc()) ->
    {error, term()}.
put(_Coll, _Key, _Doc) ->
    {error, storage_unavailable}.
