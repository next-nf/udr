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

-module(udr_otel_app).
-moduledoc "`application` behaviour for `udr_otel`: sets up metric instruments on\n"
           "start and serves the OTEL Prometheus `/metrics` endpoint.".

-behaviour(application).

-include_lib("kernel/include/logger.hrl").

-export([start/2, stop/1]).

-define(METRICS_LISTENER, udr_otel_metrics_listener).

start(_StartType, _StartArgs) ->
    ok = udr_otel:setup_metrics(),
    ok = udr_otel:setup_instrumentation(),
    ok = start_metrics_endpoint(),
    udr_otel_sup:start_link().

stop(_State) ->
    _ = cowboy:stop_listener(?METRICS_LISTENER),
    udr_otel:clear_metrics().

%% Serve the OTEL Prometheus exporter's text exposition at GET /metrics, scraping
%% the `udr_prometheus_reader` configured under opentelemetry_experimental. A
%% dedicated listener keeps the scrape endpoint off the SBI/provisioning surfaces
%% and out of their HTTP instrumentation (no opentelemetry_cowboy_h here, so a
%% scrape does not itself emit http.server.* metrics). A bind failure is logged,
%% not fatal: observability must never prevent the node from booting.
start_metrics_endpoint() ->
    Port = application:get_env(udr_otel, metrics_port, 9464),
    Ip   = application:get_env(udr_otel, metrics_ip, {127, 0, 0, 1}),
    Opts = #{server_name => udr_prometheus_reader,
             add_total_suffix => true, add_scope_info => false},
    Dispatch = cowboy_router:compile([{'_', [{"/metrics", otel_cowboy_prometheus_h, Opts}]}]),
    case cowboy:start_clear(?METRICS_LISTENER, [{port, Port}, {ip, Ip}],
                            #{env => #{dispatch => Dispatch}}) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            ?LOG_WARNING("udr_otel: /metrics endpoint not started on port ~p: ~p",
                         [Port, Reason]),
            ok
    end.
