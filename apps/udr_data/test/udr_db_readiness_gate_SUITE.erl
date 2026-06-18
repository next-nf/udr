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
-module(udr_db_readiness_gate_SUITE).
-moduledoc "Asserts the database.md §6.4 readiness gate: `udr_db:ready/0` must be\n"
           "true once the `udr_data` application has started, and (by OTP dependency\n"
           "order) the collections must exist before any listener app can start.\n"
           "Runs entirely on Mnesia-ram — no external infrastructure required.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([ready_after_udr_data_start/1,
         await_ready_returns_ok/1,
         collections_exist_after_udr_data_start/1]).

all() ->
    [ready_after_udr_data_start,
     await_ready_returns_ok,
     collections_exist_after_udr_data_start].

%%--------------------------------------------------------------------
%% Suite lifecycle
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    %% Reset backend cache so the env above is picked up.
    catch persistent_term:erase({udr_db, backend}),
    ok = udr_db_ct:setup_mnesia_ram(),
    %% Start udr_db and udr_data (which includes the readiness gate in start/2).
    {ok, Started} = application:ensure_all_started(udr_data),
    [{started, Started} | Config].

end_per_suite(Config) ->
    [application:stop(A) || A <- lists:reverse(?config(started, Config))],
    udr_db_ct:teardown_mnesia(),
    ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

%% Once udr_data has started, udr_db:ready/0 must return true.
%% This verifies that the gate (ensure_collections + await_ready called in
%% udr_data_app:start/2) completed successfully before the app was declared up.
ready_after_udr_data_start(_Config) ->
    ?assert(udr_db:ready()),
    ok.

%% udr_db:await_ready/1 with a generous timeout must return ok when the
%% backend is already up (idempotent / non-blocking when ready).
await_ready_returns_ok(_Config) ->
    ?assertEqual(ok, udr_db:await_ready(5000)),
    ok.

%% All three udr_data collections must exist in Mnesia after udr_data starts.
%% mnesia:table_info/2 raises an exception if the table is unknown; the test
%% fails if any collection is missing.
collections_exist_after_udr_data_start(_Config) ->
    Collections = [auth_subscription, subscription_data, access_registration],
    lists:foreach(fun(Coll) ->
        Type = mnesia:table_info(Coll, type),
        ?assertEqual(set, Type)
    end, Collections),
    ok.
