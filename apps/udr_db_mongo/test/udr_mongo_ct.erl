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
-module(udr_mongo_ct).
-moduledoc """
Shared Common Test helper that makes a MongoDB available to the mongo-backed
suites, choosing the source by environment:

  * **In CI** (`CI=true`, set automatically by GitHub Actions) it does NOT start
    podman -- mongo is provided as a service container -- and simply probes it at
    `MONGO_HOST`/`MONGO_PORT` (default `127.0.0.1:27017`).
  * **Locally** it self-manages a `mongo:7` container via podman on the suite's
    own port (skipping if podman is unavailable).

`start/2` returns the effective `{Host, Port}` so callers point `udr_db`'s
`backend_opts` at whichever mongo they got. Both suites can share one CI service
since they use distinct databases. The readiness probe is the proven raw-TCP one:
a connection mongod holds open (recv times out rather than returning closed) means
it is past first-boot churn -- and gen_tcp's plain return values mean no
tcp_closed CRASH REPORT spam.
""".
-export([start/2, stop/1, in_ci/0]).

%% Require several CONSECUTIVE fresh connections to survive a short hold: a
%% freshly-booted mongo accepts then drops connections during first-boot churn,
%% intermittently and per-connection, so one success is not enough.
-define(NEED_STABLE, 3).
-define(ATTEMPTS, 60).

-doc """
Make mongo available for a suite. `Container` is the local podman container name
and `LocalPort` the host port used locally; both are ignored in CI (the service
is used instead). Returns the effective connection target or a skip reason.
""".
-spec start(string(), inet:port_number()) ->
    {ok, #{host := string(), port := inet:port_number()}} | {skip, term()}.
start(Container, LocalPort) ->
    case in_ci() of
        true ->
            Host = ci_host(),
            Port = ci_port(),
            {ok, _} = application:ensure_all_started(mongodb),
            case wait_ready(Host, Port) of
                ok    -> {ok, #{host => Host, port => Port}};
                Error -> {skip, {mongo_service_unreachable, Host, Port, Error}}
            end;
        false ->
            case os:find_executable("podman") of
                false ->
                    {skip, "podman/mongo:7 unavailable"};
                _ ->
                    {ok, _} = application:ensure_all_started(mongodb),
                    case start_container(Container, LocalPort) of
                        ok    -> {ok, #{host => "127.0.0.1", port => LocalPort}};
                        Error -> {skip, {mongo_container_failed, Error}}
                    end
            end
    end.

-doc "Tear down the local container; a no-op in CI (the service is GitHub-managed).".
-spec stop(string()) -> ok.
stop(Container) ->
    case in_ci() of
        true  -> ok;
        false -> _ = os:cmd("podman stop " ++ Container ++ " 2>/dev/null"), ok
    end.

-doc "Whether we are running under CI (GitHub Actions sets CI=true).".
-spec in_ci() -> boolean().
in_ci() -> os:getenv("CI") =:= "true".

%% --- CI service target ----------------------------------------------------

ci_host() ->
    case os:getenv("MONGO_HOST") of false -> "127.0.0.1"; H -> H end.

ci_port() ->
    case os:getenv("MONGO_PORT") of false -> 27017; P -> list_to_integer(P) end.

%% --- local podman container lifecycle -------------------------------------

start_container(Container, Port) ->
    _ = os:cmd("podman rm -f " ++ Container ++ " 2>/dev/null"),
    Cmd = "podman run -d --rm --name " ++ Container ++
          " -p " ++ integer_to_list(Port) ++ ":27017 mongo:7 2>&1",
    Out = os:cmd(Cmd),
    case string:find(Out, "Error") of
        nomatch -> wait_ready("127.0.0.1", Port);
        _       -> {error, Out}
    end.

%% --- readiness probe ------------------------------------------------------

wait_ready(Host, Port) -> wait_ready(Host, Port, ?ATTEMPTS, 0).

wait_ready(_Host, _Port, 0, _) -> {error, timeout};
wait_ready(_Host, _Port, _N, Consec) when Consec >= ?NEED_STABLE -> ok;
wait_ready(Host, Port, N, Consec) ->
    case probe(Host, Port) of
        ok    -> wait_ready(Host, Port, N - 1, Consec + 1);
        _Fail -> timer:sleep(1000), wait_ready(Host, Port, N - 1, 0)
    end.

probe(Host, Port) ->
    case gen_tcp:connect(Host, Port, [binary, {active, false}], 2000) of
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
