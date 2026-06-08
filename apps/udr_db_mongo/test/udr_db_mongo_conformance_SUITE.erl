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
    case udr_mongo_ct:start(?CONTAINER, ?PORT) of
        {ok, #{host := Host, port := Port}} ->
            %% Load udr_db FIRST so our backend override survives: setting
            %% env before the app is loaded would be reset to the .app
            %% default (udr_db_ets) when ensure_all_started loads it.
            _ = application:load(udr_db),
            application:set_env(udr_db, backend, udr_db_mongo),
            application:set_env(udr_db, backend_opts,
                                #{database => ?DB, host => Host, port => Port}),
            persistent_term:erase({udr_db, backend}),
            {ok, Started} = application:ensure_all_started(udr_db),
            drop_collection(),
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

conformance(_Config) ->
    [ begin ct:log("scenario: ~s", [Name]), Fun() end
      || {Name, Fun} <- udr_db_conformance:scenarios() ],
    ok.

%% --- helpers --------------------------------------------------------------

drop_collection() ->
    Conn = udr_db_mongo_conn:conn(),
    _ = mc_worker_api:delete(Conn, <<"c">>, #{}),
    ok.
