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
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([conformance/1]).

-define(CONTAINER, "udr-mongo-conformance").
-define(PORT, 27017).
-define(DB, <<"udr_conformance">>).

all() ->
    [conformance].

init_per_suite(Config) ->
    case available() of
        true ->
            %% Load udr_db FIRST so our backend override survives: setting
            %% env before the app is loaded would be reset to the .app
            %% default (udr_db_ets) when ensure_all_started loads it.
            _ = application:load(udr_db),
            application:set_env(udr_db, backend, udr_db_mongo),
            application:set_env(udr_db, backend_opts,
                                #{database => ?DB, host => "127.0.0.1", port => ?PORT}),
            persistent_term:erase({udr_db, backend}),
            {ok, Started} = application:ensure_all_started(udr_db),
            drop_collection(),
            [{started, Started} | Config];
        false ->
            {skip, "podman/mongo:7 unavailable"}
    end.

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    persistent_term:erase({udr_db, backend}),
    stop_mongo(),
    ok.

conformance(_Config) ->
    [ begin ct:log("scenario: ~s", [Name]), Fun() end
      || {Name, Fun} <- udr_db_conformance:scenarios() ],
    ok.

%% --- mongo container lifecycle ------------------------------------------

podman() -> os:find_executable("podman").

start_mongo() ->
    _ = os:cmd("podman rm -f " ?CONTAINER " 2>/dev/null"),
    Cmd = "podman run -d --rm --name " ?CONTAINER
          " -p " ++ integer_to_list(?PORT) ++ ":27017 mongo:7 2>&1",
    Out = os:cmd(Cmd),
    case string:find(Out, "Error") of
        nomatch -> wait_ready(60);
        _       -> {error, Out}
    end.

stop_mongo() -> os:cmd("podman stop " ?CONTAINER " 2>/dev/null"), ok.

available() ->
    podman() =/= false andalso
        begin
            {ok, _} = application:ensure_all_started(mongodb),
            start_mongo() =:= ok
        end.

%% A freshly-booted mongo container accepts connections during its early
%% startup window and then closes them again (first-boot churn). Crucially the
%% churn is INTERMITTENT and per-connection: one socket may survive a couple of
%% seconds while another, opened moments later, is dropped. A single successful
%% probe is therefore not enough -- the backend's own connection, opened just
%% after, could still be killed. So we require several CONSECUTIVE fresh
%% connections to each survive a short hold, which only happens once mongo is
%% comfortably past the churn window.
-define(NEED_STABLE, 3).

wait_ready(N) -> wait_ready(N, 0).

wait_ready(0, _) -> {error, timeout};
wait_ready(_N, Consec) when Consec >= ?NEED_STABLE -> ok;
wait_ready(N, Consec) ->
    case probe() of
        ok    -> wait_ready(N - 1, Consec + 1);
        _Fail -> timer:sleep(1000), wait_ready(N - 1, 0)
    end.

%% Raw TCP readiness: a connection that mongod holds open (recv times out rather
%% than returning {error,closed}) means mongod is past its first-boot churn and
%% stably accepting external connections. gen_tcp errors are plain return values
%% -- no linked process, so no tcp_closed CRASH REPORT spam.
probe() ->
    case gen_tcp:connect("127.0.0.1", ?PORT, [binary, {active, false}], 2000) of
        {ok, Sock} ->
            timer:sleep(800),
            R = case gen_tcp:recv(Sock, 0, 200) of
                    {error, timeout} -> ok;            %% held open -> ready
                    {error, closed}  -> {error, closed};
                    {error, _} = E   -> E;
                    {ok, _}          -> ok
                end,
            gen_tcp:close(Sock),
            R;
        {error, _} = E -> E
    end.

drop_collection() ->
    Conn = udr_db_mongo_conn:conn(),
    _ = mc_worker_api:delete(Conn, <<"c">>, #{}),
    ok.
