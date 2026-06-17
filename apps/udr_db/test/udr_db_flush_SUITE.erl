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
-module(udr_db_flush_SUITE).
-moduledoc "Placeholder suite: the `flush/0` operation has been removed from the\n"
           "`udr_db` contract (database.md §2.3). Backends are cleared in tests by\n"
           "calling `mnesia:clear_table/1` directly.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([flush_removed/1]).

all() -> [flush_removed].

flush_removed(_Config) ->
    %% flush/0 has been removed from the udr_db contract. Verify the function
    %% is not exported (it was removed in the ETS->Mnesia cutover).
    Exports = udr_db:module_info(exports),
    ?assertEqual(false, lists:keymember(flush, 1, Exports)),
    ok.
