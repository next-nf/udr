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

-module(udr_db_ets_SUITE).
-moduledoc "Placeholder suite: the `udr_db_ets` backend has been removed (replaced by\n"
           "`udr_db_mnesia`). This file exists to replace a stale build artifact from\n"
           "the pre-cutover codebase; see `udr_db_mnesia_SUITE` for the current backend\n"
           "conformance tests.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([ets_backend_removed/1]).

all() -> [ets_backend_removed].

ets_backend_removed(_Config) ->
    %% The ETS backend (udr_db_ets) was removed in the Mnesia cutover.
    %% Verify the module is no longer available; all backend tests now
    %% live in udr_db_mnesia_SUITE and udr_db_conformance.
    ?assertEqual(false, erlang:module_loaded(udr_db_ets)),
    %% code:ensure_loaded/1 returns {error, nofile} when the beam is absent.
    ?assertMatch({error, _}, code:ensure_loaded(udr_db_ets)),
    ok.
