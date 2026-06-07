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
-module(udr_db_mongo_conn).
-moduledoc "Owns the MongoDB connection; lazily starts the `mongodb` app, connects, and\n"
           "caches the connection handle in persistent_term for the stateless backend funs.".
-behaviour(gen_server).
-export([start_link/1, conn/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(PT_KEY, {udr_db_mongo, conn}).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

-doc "The cached MongoDB connection handle.".
-spec conn() -> pid().
conn() ->
    persistent_term:get(?PT_KEY).

-spec init(map()) -> {ok, map()}.
init(Opts) ->
    process_flag(trap_exit, true),
    {ok, _} = application:ensure_all_started(mongodb),
    ConnOpts = [{database, maps:get(database, Opts, <<"udr">>)},
                {host,     maps:get(host, Opts, "127.0.0.1")},
                {port,     maps:get(port, Opts, 27017)}
                | login_opts(Opts)],
    {ok, Conn} = mc_worker_api:connect(ConnOpts),
    persistent_term:put(?PT_KEY, Conn),
    {ok, #{conn => Conn}}.

handle_call(_R, _F, S) -> {reply, ok, S}.
handle_cast(_M, S)     -> {noreply, S}.

-spec handle_info(term(), map()) -> {noreply, map()} | {stop, term(), map()}.
handle_info({'EXIT', _Pid, Reason}, State) ->
    {stop, Reason, State};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    _ = persistent_term:erase(?PT_KEY),
    ok.

login_opts(Opts) ->
    case maps:get(login, Opts, undefined) of
        undefined -> [];
        Login -> [{login, Login},
                  {password, maps:get(password, Opts, <<>>)},
                  {auth_source, maps:get(auth_source, Opts, <<"admin">>)}]
    end.
