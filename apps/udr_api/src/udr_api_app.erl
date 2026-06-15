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
-module(udr_api_app).
-moduledoc "Application callback: starts the provisioning Cowboy listener.".
-behaviour(application).
-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()} | {error, term()}.
start(_StartType, _StartArgs) ->
    Port = application:get_env(udr_api, port, 8090),
    Ip   = application:get_env(udr_api, ip, {127,0,0,1}),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/provision/v1/subscribers/:imsi", udr_api_subscriber_h, []}
        ]}
    ]),
    %% HTTP server metrics are opt-in: create the instruments once (idempotent --
    %% safe across both listeners and repeated test starts) and pass metrics_cb so
    %% opentelemetry_cowboy_h records request/response histograms. Spans are emitted
    %% by the stream handler regardless; metrics need this wiring.
    ok = opentelemetry_cowboy_experimental_h:init(),
    {ok, _} = cowboy:start_clear(udr_api_listener,
                                 [{port, Port}, {ip, Ip}],
                                 #{env => #{dispatch => Dispatch},
                                   otel_opts => #{metrics_cb =>
                                       fun opentelemetry_cowboy_experimental_h:metrics_cb/5},
                                   stream_handlers => [opentelemetry_cowboy_h, cowboy_stream_h]}),
    udr_api_sup:start_link().

-spec stop(term()) -> ok.
stop(_State) ->
    _ = cowboy:stop_listener(udr_api_listener),
    ok.
