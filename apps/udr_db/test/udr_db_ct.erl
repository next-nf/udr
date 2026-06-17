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

-export([setup_mnesia/0, setup_mnesia_ram/0, setup_mnesia_disc/0, teardown_mnesia/0]).

-doc "Start Mnesia with a clean schema on this node.\n"
     "Creates a disc schema (needed so both ram_copies and disc_copies tables can coexist\n"
     "in the same Mnesia instance). Safe to call multiple times.\n"
     "\n"
     "For test suites that use only ram_copies and want to avoid disc I/O, prefer\n"
     "`setup_mnesia_ram/0` instead.".
-spec setup_mnesia() -> ok.
setup_mnesia() ->
    setup_mnesia_disc().

-doc "Start Mnesia with a ram-only schema (no disc). Tables must use `ram_copies`.\n"
     "Faster than `setup_mnesia_disc/0`; no schema files are written to disk.".
-spec setup_mnesia_ram() -> ok.
setup_mnesia_ram() ->
    application:stop(mnesia),
    ok = mnesia:delete_schema([node()]),
    %% Do NOT call create_schema — the default in-memory schema is sufficient
    %% for ram_copies tables and avoids any disc dependency.
    ok = application:start(mnesia).

-doc "Start Mnesia with a disc schema (required for `disc_copies` tables).\n"
     "Calls `mnesia:create_schema/1` to initialise schema files before starting.".
-spec setup_mnesia_disc() -> ok.
setup_mnesia_disc() ->
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
