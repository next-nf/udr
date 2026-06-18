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
           "`udr_db_mnesia` with both `ram_copies` and `disc_copies` storage tiers\n"
           "(database.md §3.3, §8.1).".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2,
         init_per_testcase/2, end_per_testcase/2]).
-export([run_conformance/1]).

%% Collection atoms used per group — different names avoid cross-group interference.
-define(RAM_COLL,      conf_mnesia_ram).
-define(RAM_IDX_COLL,  conf_mnesia_ram_idx).
-define(DISC_COLL,     conf_mnesia_disc).
-define(DISC_IDX_COLL, conf_mnesia_disc_idx).

all() ->
    [{group, ram}, {group, disc}].

groups() ->
    [
     {ram,  [sequence], [run_conformance]},
     {disc, [sequence], [run_conformance]}
    ].

%%--------------------------------------------------------------------
%% Suite-level init/end: start the gen_server once for the whole suite.
%% Schema lifecycle is per-group because ram and disc need different setups.
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    {ok, _Pid} = udr_db_mnesia:start_link(#{}),
    Config.

end_per_suite(_Config) ->
    catch gen_server:stop(udr_db_mnesia),
    ok.

%%--------------------------------------------------------------------
%% Group-level init/end: set up the right Mnesia schema and collections.
%%--------------------------------------------------------------------

init_per_group(ram, Config) ->
    ok = udr_db_ct:setup_mnesia_ram(),
    ok = udr_db_mnesia:ensure_collection(?RAM_COLL,     #{storage => ram_copies}),
    ok = udr_db_mnesia:ensure_collection(?RAM_IDX_COLL, #{indexes => [<<"idx">>],
                                                          storage => ram_copies}),
    ok = udr_db_mnesia:wait_ready([?RAM_COLL, ?RAM_IDX_COLL]),
    [{coll, ?RAM_COLL}, {idx_coll, ?RAM_IDX_COLL} | Config];

init_per_group(disc, Config) ->
    %% disc bootstrap: create_schema (disc only) → ensure_collection → wait_for_tables
    ok = udr_db_ct:setup_mnesia_disc(),
    ok = udr_db_mnesia:ensure_collection(?DISC_COLL,     #{storage => disc_copies}),
    ok = udr_db_mnesia:ensure_collection(?DISC_IDX_COLL, #{indexes => [<<"idx">>],
                                                           storage => disc_copies}),
    ok = udr_db_mnesia:wait_ready([?DISC_COLL, ?DISC_IDX_COLL]),
    [{coll, ?DISC_COLL}, {idx_coll, ?DISC_IDX_COLL} | Config].

end_per_group(_Group, _Config) ->
    %% Stop Mnesia and delete schema files so repeated runs start clean.
    udr_db_ct:teardown_mnesia(),
    ok.

%%--------------------------------------------------------------------
%% Per-testcase: clear rows between cases (keeps scenarios isolated).
%%--------------------------------------------------------------------

init_per_testcase(_TestCase, Config) ->
    Coll    = proplists:get_value(coll,     Config),
    IdxColl = proplists:get_value(idx_coll, Config),
    mnesia:clear_table(Coll),
    mnesia:clear_table(IdxColl),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

run_conformance(Config) ->
    Coll    = proplists:get_value(coll,     Config),
    IdxColl = proplists:get_value(idx_coll, Config),
    Scenarios = udr_db_conformance:scenarios(udr_db_mnesia, Coll, IdxColl),
    lists:foreach(
        fun({Name, Fun}) ->
            ct:log("scenario: ~s", [Name]),
            Fun()
        end,
        Scenarios).
