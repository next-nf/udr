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
-module(udr_diameter_srv).
-moduledoc "Owns the S6a diameter service and its TCP listener.".
-behaviour(gen_server).
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(SVC, udr_diameter).

-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    OH = application:get_env(udr_diameter, origin_host, "hss.local"),
    OR = application:get_env(udr_diameter, origin_realm, "local"),
    Listen = application:get_env(udr_diameter, listen, [{tcp, {127,0,0,1}, 3868}]),
    SvcOpts =
        [{'Origin-Host', OH}, {'Origin-Realm', OR},
         {'Vendor-Id', 10415}, {'Product-Name', "next-udr"},
         {'Auth-Application-Id', [16777251]},
         {'Vendor-Specific-Application-Id',
            [[{'Vendor-Id', 10415}, {'Auth-Application-Id', [16777251]}]]},
         {string_decode, false},
         {decode_format, map},
         {application, [{alias, s6a},
                        {dictionary, diameter_3gpp_s6a},
                        {module, udr_diameter_s6a}]}],
    ok = diameter:start_service(?SVC, SvcOpts),
    ok = lists:foreach(fun add_listener/1, Listen),
    {ok, #{}}.

add_listener({tcp, IP, Port}) ->
    Opts = [{transport_module, diameter_tcp},
            {transport_config, [{reuseaddr, true}, {ip, IP}, {port, Port}]}],
    {ok, _} = diameter:add_transport(?SVC, {listen, Opts}),
    ok.

handle_call(_R, _F, S) -> {reply, ok, S}.
handle_cast(_M, S)     -> {noreply, S}.

handle_info(_Msg, State) ->
    {noreply, State}.

-spec terminate(term(), term()) -> ok.
terminate(_Reason, _State) ->
    _ = diameter:stop_service(?SVC),
    ok.
