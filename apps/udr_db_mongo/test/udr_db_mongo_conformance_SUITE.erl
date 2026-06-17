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
-module(udr_db_mongo_conformance_SUITE).
-moduledoc "Runs the backend-agnostic `udr_db_conformance` scenarios against the\n"
           "`udr_db_mongo` backend via a testcontainer (or CI Mongo service).\n"
           "\n"
           "Collections: `conf_plain` (no indexes) and `conf_idx` (with `<<\"idx\">>` index)\n"
           "are set up in `init_per_suite` via `udr_db_mongo:ensure_collection/2`.\n"
           "Content is cleared before each test case to ensure independence.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([conformance/1]).

-define(CONTAINER, "udr-mongo-conformance").
-define(PORT, 27017).
-define(DB, <<"udr_conformance">>).
-define(COLL,     conf_plain).
-define(IDX_COLL, conf_idx).

all() ->
    [conformance].

init_per_suite(Config) ->
    case udr_mongo_ct:start(?CONTAINER, ?PORT) of
        {ok, #{host := Host, port := Port}} ->
            %% Load udr_db FIRST so our backend override survives: setting
            %% env before the app is loaded would be reset to the .app
            %% default (udr_db_mnesia) when ensure_all_started loads it.
            _ = application:load(udr_db),
            application:set_env(udr_db, backend, udr_db_mongo),
            application:set_env(udr_db, backend_opts,
                                #{database => ?DB, host => Host, port => Port}),
            persistent_term:erase({udr_db, backend}),
            {ok, Started} = application:ensure_all_started(udr_db),
            %% Declare collections via the backend directly (conformance suite
            %% calls the backend module, not the facade).
            ok = udr_db_mongo:ensure_collection(?COLL, #{}),
            ok = udr_db_mongo:ensure_collection(?IDX_COLL, #{indexes => [<<"idx">>]}),
            [{started, Started} | Config];
        {skip, Reason} ->
            {skip, Reason}
    end.

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    persistent_term:erase({udr_db, backend}),
    udr_mongo_ct:stop(?CONTAINER),
    ok.

init_per_testcase(_Name, Config) ->
    drop_collections(),
    Config.

end_per_testcase(_Name, _Config) ->
    ok.

conformance(_Config) ->
    Scenarios = udr_db_conformance:scenarios(udr_db_mongo, ?COLL, ?IDX_COLL),
    lists:foreach(
        fun({Name, Fun}) ->
            ct:log("scenario: ~s", [Name]),
            Fun()
        end,
        Scenarios),
    ok.

%%--------------------------------------------------------------------
%% helpers
%%--------------------------------------------------------------------

drop_collections() ->
    Conn = udr_db_mongo_conn:conn(),
    _ = mc_worker_api:delete(Conn, atom_to_binary(?COLL, utf8), #{}),
    _ = mc_worker_api:delete(Conn, atom_to_binary(?IDX_COLL, utf8), #{}),
    ok.
