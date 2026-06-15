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

-module(udr_otel).
-moduledoc "OpenTelemetry metric instruments for the S6a path and a recording helper.".
-export([setup_metrics/0, setup_instrumentation/0, clear_metrics/0, record_s6a/3]).

-include_lib("kernel/include/logger.hrl").

-define(METER, {?MODULE, meter}).
-define(REQUESTS, 's6a.requests').
-define(DURATION, 's6a.handler.duration').

-spec setup_metrics() -> ok.
setup_metrics() ->
    %% The experimental metrics API records by (meter, instrument-name), not by an
    %% instrument handle: create/3 registers the instrument with the meter, then
    %% otel_counter:add/5 and otel_histogram:record/5 reference it by name. Cache
    %% the meter so the hot path does not resolve it per request.
    %% Resolve this app's meter via its instrumentation scope (as the otel_meter.hrl
    %% ?current_meter macro does); get_meter/1 expects a scope, not a bare module atom.
    Meter = opentelemetry_experimental:get_meter(opentelemetry:get_application_scope(?MODULE)),
    %% Unit is the annotation unit '{request}', not '1': under the OTEL->Prometheus
    %% transform a dimensionless '1' counter becomes `_ratio_total` (e.g.
    %% s6a_requests_ratio_total), whereas an annotation unit is stripped, giving the
    %% clean s6a_requests_total. This also matches the org diameter instrumentation,
    %% which uses '{request}'.
    _ = otel_meter:create_counter(Meter, ?REQUESTS,
                                  #{description => <<"S6a requests">>, unit => '{request}'}),
    _ = otel_meter:create_histogram(Meter, ?DURATION,
                                    #{description => <<"S6a handler latency (s)">>, unit => s}),
    persistent_term:put(?METER, Meter),
    ok.

-doc "Register the OTEL instrumentation libraries' metrics (per the org observability\n"
     "policy): HTTP server histograms, diameter request/connection counters, and the\n"
     "BEAM/VM + process observable gauges. The diameter/beam/process instruments are\n"
     "observable (pull-based) callbacks; the HTTP histograms are recorded by the cowboy\n"
     "stream handler's metrics_cb (wired into each listener). Each library setup is\n"
     "isolated so a fault in one -- or a metrics subsystem that is not running, as in\n"
     "some test contexts -- never prevents node boot.".
-spec setup_instrumentation() -> ok.
setup_instrumentation() ->
    setup_each([{opentelemetry_cowboy_experimental_h, init,           "HTTP server"},
                {opentelemetry_diameter_metrics,      setup,          "diameter"},
                {opentelemetry_beam_metrics,          setup,          "BEAM/VM"},
                {opentelemetry_process_metrics,       setup,          "process"}]),
    ok.

setup_each(Specs) ->
    lists:foreach(
      fun({Mod, Fun, What}) ->
          try Mod:Fun() of
              _ -> ok
          catch
              Class:Reason:St ->
                  ?LOG_WARNING("udr_otel: ~ts instrumentation setup failed "
                               "(~p:~p); metrics for it will be absent: ~p",
                               [What, Mod, Fun, {Class, Reason, St}])
          end
      end, Specs).

-spec clear_metrics() -> ok.
clear_metrics() ->
    %% Drop the cached meter when the app stops; otherwise a later record_s6a/3
    %% would record against a torn-down meter provider.
    _ = persistent_term:erase(?METER),
    ok.

-spec record_s6a(atom(), atom(), non_neg_integer()) -> ok.
record_s6a(Command, Result, DurationNative) ->
    %% Skip silently if the instruments haven't been created yet (setup_metrics/0
    %% runs at app start): never let a missing metrics subsystem fail a request.
    case persistent_term:get(?METER, undefined) of
        undefined -> ok;
        Meter ->
            Ctx = otel_ctx:get_current(),
            Attrs = #{'s6a.command' => Command, 's6a.result' => Result},
            _ = otel_counter:add(Ctx, Meter, ?REQUESTS, 1, Attrs),
            Secs = DurationNative / erlang:convert_time_unit(1, second, native),
            _ = otel_histogram:record(Ctx, Meter, ?DURATION, Secs, Attrs),
            ok
    end.
