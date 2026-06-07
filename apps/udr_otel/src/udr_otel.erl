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
-export([setup_metrics/0, clear_metrics/0, record_s6a/3]).

-define(REQ, {?MODULE, s6a_requests}).
-define(DUR, {?MODULE, s6a_duration}).

-spec setup_metrics() -> ok.
setup_metrics() ->
    Meter = opentelemetry_experimental:get_meter(?MODULE),
    Counter = otel_meter:create_counter(Meter, 's6a.requests',
                                        #{description => <<"S6a requests">>, unit => '1'}),
    Hist = otel_meter:create_histogram(Meter, 's6a.handler.duration',
                                       #{description => <<"S6a handler latency (s)">>, unit => s}),
    persistent_term:put(?REQ, Counter),
    persistent_term:put(?DUR, Hist),
    ok.

-spec clear_metrics() -> ok.
clear_metrics() ->
    %% Drop the cached instrument handles when the app stops; otherwise stale
    %% handles outlive the meter provider's ETS tables and a later record_s6a/3
    %% would call into a torn-down SDK.
    _ = persistent_term:erase(?REQ),
    _ = persistent_term:erase(?DUR),
    ok.

-spec record_s6a(atom(), atom(), non_neg_integer()) -> ok.
record_s6a(Command, Result, DurationNative) ->
    %% Skip silently if the instruments haven't been created yet (setup_metrics/0
    %% runs at app start): never let a missing metrics subsystem fail a request.
    case {persistent_term:get(?REQ, undefined), persistent_term:get(?DUR, undefined)} of
        {undefined, _} -> ok;
        {_, undefined} -> ok;
        {Counter, Hist} ->
            Ctx = otel_ctx:get_current(),
            Attrs = #{'s6a.command' => Command, 's6a.result' => Result},
            _ = otel_counter:add(Ctx, Counter, 1, Attrs),
            Secs = DurationNative / erlang:convert_time_unit(1, second, native),
            _ = otel_histogram:record(Ctx, Hist, Secs, Attrs),
            ok
    end.
