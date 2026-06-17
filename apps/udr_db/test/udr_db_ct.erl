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
-module(udr_db_ct).
-moduledoc "Shared Common Test helper for suites that need a Mnesia node.\n"
           "See database.md §8.6.".

-export([setup_mnesia/0, teardown_mnesia/0]).

-doc "Start Mnesia with a clean in-memory schema on this node.\n"
     "Safe to call multiple times — stops and wipes any existing schema first.".
-spec setup_mnesia() -> ok.
setup_mnesia() ->
    application:stop(mnesia),
    ok = mnesia:delete_schema([node()]),
    ok = mnesia:create_schema([node()]),
    ok = application:start(mnesia).

-doc "Stop Mnesia and delete the schema. Call in `end_per_suite`/`end_per_group`.".
-spec teardown_mnesia() -> ok.
teardown_mnesia() ->
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    ok.
