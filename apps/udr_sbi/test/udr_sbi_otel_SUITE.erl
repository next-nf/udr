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
-module(udr_sbi_otel_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([http_server_span/1]).

-define(PORT, 18082).

all() -> [http_server_span].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    application:set_env(opentelemetry, span_processor, simple),
    application:set_env(opentelemetry, traces_exporter, {udr_otel_pid_exporter, #{}}),
    application:set_env(opentelemetry_experimental, readers,
                       [#{module => otel_metric_reader, config => #{}}]),
    application:load(udr_sbi),
    application:set_env(udr_sbi, port, ?PORT),
    {ok, S1} = application:ensure_all_started(udr_otel),
    {ok, S2} = application:ensure_all_started(udr_sbi),
    {ok, _}  = application:ensure_all_started(inets),
    [{started, lists:usort(S1 ++ S2)} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    ok.

%% a GET produces an HTTP server span
http_server_span(_Config) ->
    udr_otel_pid_exporter:capture_to(self()),
    U = "http://127.0.0.1:" ++ integer_to_list(?PORT)
        ++ "/nudr-dr/v1/subscription-data/imsi-1/authentication-data/authentication-subscription",
    {ok, _} = httpc:request(get, {U, []}, [], [{body_format, binary}]),
    ?assert(received_http_span(2000)),
    ok.

received_http_span(Timeout) ->
    receive
        {otel_span, #{name := Name, kind := Kind}} ->
            NameBin = iolist_to_binary([Name]),
            case {binary:match(NameBin, <<"HTTP">>), Kind} of
                {nomatch, _} -> received_http_span(Timeout);
                _            -> true
            end
    after Timeout -> false
    end.
