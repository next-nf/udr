%%%------------------------------------------------------------------------
%% Vendored from the next-nf opentelemetry-erlang fork
%% (samples/otel_cowboy_prometheus_h.erl, branch
%% feature/prometheus-exporter-for-upstream). It ships as sample code there, not
%% as a compiled module in any application, so udr carries its own copy to serve
%% the OTEL Prometheus exporter's /metrics endpoint (see udr_otel_app). Keep this
%% in sync with upstream; drop it once the fork ships the handler as a module.
%%
%% Copyright 2024, OpenTelemetry Authors
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% @doc
%% Serves the OTEL Prometheus exporter's text exposition for a named
%% otel_metric_reader_prometheus reader. Configure opentelemetry_experimental with:
%%
%%     {opentelemetry_experimental,
%%      [{readers,
%%        [#{module => otel_metric_reader_prometheus,
%%           config => #{add_scope_info => false,
%%                       add_total_suffix => true,
%%                       server_name => udr_prometheus_reader}}]}]}
%%
%% and add a cowboy route:
%%
%%  {"/metrics/[:registry]", otel_cowboy_prometheus_h, #{server_name => udr_prometheus_reader}}
%%
%% @end
%%%-------------------------------------------------------------------------
-module(otel_cowboy_prometheus_h).
-moduledoc false.

-behavior(cowboy_rest).

-export([init/2, content_types_provided/2,
         handle_request_text/2,
         allowed_methods/2]).

-ignore_xref([handle_request_text/2]).

init(Req, Opts) ->
    {cowboy_rest, Req, Opts}.

allowed_methods(Req, State) ->
    {[<<"GET">>], Req, State}.

content_types_provided(Req, State) ->
    {[{{<<"text">>, <<"plain">>, '*'}, handle_request_text}], Req, State}.

handle_request_text(Req0, #{server_name := ServerName} = State) ->
    Serializer = fun(Metrics, Resource) ->
                         otel_metric_serializer_prometheus:serialize(Metrics, Resource, State)
                 end,
    Metrics = otel_metric_reader:collect(ServerName, Serializer),
    Body = iolist_to_binary(Metrics),
    Req = cowboy_req:reply(200, #{}, Body, Req0),
    {stop, Req, State}.
