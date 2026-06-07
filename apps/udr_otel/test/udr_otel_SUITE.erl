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

-module(udr_otel_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("opentelemetry_api/include/otel_tracer.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([manual_span/1, s6a_metric/1]).

all() -> [manual_span, s6a_metric].

init_per_suite(Config) ->
    application:set_env(opentelemetry, span_processor, simple),
    application:set_env(opentelemetry, traces_exporter, {udr_otel_pid_exporter, #{}}),
    application:set_env(opentelemetry, resource, #{service => #{name => <<"test">>}}),
    application:set_env(opentelemetry_experimental, readers,
                       [#{module => otel_metric_reader, config => #{}}]),
    {ok, Started} = application:ensure_all_started(udr_otel),
    [{started, Started} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    ok.

%% a manual span is exported (captured via the pid exporter)
manual_span(_Config) ->
    udr_otel_pid_exporter:capture_to(self()),
    ?with_span(<<"test.span">>, #{},
               fun(_) -> ?set_attributes(#{<<"k">> => <<"v">>}), ok end),
    receive
        {otel_span, #{name := <<"test.span">>} = S} ->
            ?assertEqual(<<"v">>, maps:get(<<"k">>, maps:get(attributes, S)))
    after 2000 -> ?assert(false)
    end,
    ok.

%% S6a metric recording runs without error
s6a_metric(_Config) ->
    ?assertEqual(ok, udr_otel:record_s6a('AIR', success, 1000)),
    ok.
