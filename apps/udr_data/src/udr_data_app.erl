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
-module(udr_data_app).
-moduledoc "Application callback for `udr_data`. Declares all collections at startup\n"
           "and blocks on the DB-readiness gate (database.md §6.4) before returning,\n"
           "so that listener apps that depend on `udr_data` are never started until\n"
           "the backend has completed its initialisation (`wait_for_tables` returned).".
-behaviour(application).

-export([start/2, stop/1]).

-define(AWAIT_TIMEOUT_MS, 30000).

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_StartType, _StartArgs) ->
    ok = udr_data:ensure_collections(),
    %% Readiness gate (database.md §6.4): block until the backend reports ready.
    %% For the Mnesia backend this calls mnesia:wait_for_tables/2 for all local
    %% tables. Since udr_sbi, udr_api, and udr_hss (and via it, udr_diameter)
    %% all list udr_data in their .app.src `applications`, OTP will not start
    %% any of those apps until this start/2 returns — so no listener can bind
    %% before the DB is ready. No deadlock risk: readiness depends only on the
    %% Mnesia table-loading state, not on any listener process being alive.
    ok = udr_db:await_ready(?AWAIT_TIMEOUT_MS),
    %% udr_data has no supervisor of its own; return a placeholder pid.
    %% The application framework requires {ok, Pid} so we return a simple
    %% dummy supervisor with no children.
    udr_data_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
