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
-module(udr_db_mnesia_SUITE).
-moduledoc "Common Test suite: runs the full `udr_db_conformance` scenario set against\n"
           "`udr_db_mnesia` with `ram_copies` storage.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([run_conformance/1]).

-define(COLL,     conf_mnesia_basic).
-define(IDX_COLL, conf_mnesia_idx).

all() -> [run_conformance].

init_per_suite(Config) ->
    ok = udr_db_ct:setup_mnesia(),
    {ok, _Pid} = udr_db_mnesia:start_link(#{}),
    ok = udr_db_mnesia:ensure_collection(?COLL, #{storage => ram_copies}),
    ok = udr_db_mnesia:ensure_collection(?IDX_COLL, #{indexes => [<<"idx">>],
                                                      storage => ram_copies}),
    Config.

end_per_suite(_Config) ->
    udr_db_ct:teardown_mnesia(),
    catch gen_server:stop(udr_db_mnesia),
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Clear all rows between test cases to keep scenarios isolated.
    mnesia:clear_table(?COLL),
    mnesia:clear_table(?IDX_COLL),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

run_conformance(_Config) ->
    Scenarios = udr_db_conformance:scenarios(udr_db_mnesia, ?COLL, ?IDX_COLL),
    lists:foreach(
        fun({Name, Fun}) ->
            ct:log("scenario: ~s", [Name]),
            Fun()
        end,
        Scenarios).
