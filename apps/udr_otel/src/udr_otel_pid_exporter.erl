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

-module(udr_otel_pid_exporter).
-moduledoc "Test/debug OTel span exporter: forwards exported spans to a pid set via\n"
           "capture_to/1, so tests can assert spans are produced.".
-behaviour(otel_exporter_traces).
-include_lib("opentelemetry/include/otel_span.hrl").
-export([capture_to/1, init/1, export/3, shutdown/1]).

-define(PT, {?MODULE, pid}).

-spec capture_to(pid()) -> ok.
capture_to(Pid) -> persistent_term:put(?PT, Pid).

init(Config) -> {ok, Config}.

%% The trace span processors call otel_exporter_traces:export/3, which invokes
%% Module:export(SpansTid, Resource, Config). SpansTid is an ETS table of #span{}.
export(SpansTid, _Resource, _State) ->
    case persistent_term:get(?PT, undefined) of
        undefined -> ok;
        Pid ->
            ets:foldl(fun(Span, _) ->
                          Pid ! {otel_span, #{name => Span#span.name,
                                              attributes => attrs(Span#span.attributes),
                                              kind => Span#span.kind}},
                          ok
                      end, ok, SpansTid),
            ok
    end.

shutdown(_) -> ok.

attrs(A) -> try otel_attributes:map(A) catch _:_ -> A end.
