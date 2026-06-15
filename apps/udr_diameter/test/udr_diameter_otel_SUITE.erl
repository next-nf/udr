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
-module(udr_diameter_otel_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("diameter/include/diameter.hrl").
-include("s6a_test.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([air_span/1]).

all() -> [air_span].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    application:set_env(opentelemetry, span_processor, simple),
    application:set_env(opentelemetry, traces_exporter, {udr_otel_pid_exporter, #{}}),
    application:set_env(opentelemetry_experimental, readers,
                       [#{module => otel_metric_reader, config => #{}}]),
    {ok, S1} = application:ensure_all_started(udr_otel),
    {ok, S2} = application:ensure_all_started(udr_hss),
    [{started, lists:usort(S1 ++ S2)} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    ok.

caps() ->
    #diameter_caps{origin_host = {<<"hss">>, <<"mme">>}, origin_realm = {<<"r">>, <<"r">>}}.

air(Imsi) ->
    ['AIR' | #{'Session-Id' => <<"s1">>, 'Auth-Session-State' => 1,
               'Origin-Host' => <<"mme">>, 'Origin-Realm' => <<"r">>,
               'Destination-Realm' => <<"r">>, 'User-Name' => Imsi,
               'Visited-PLMN-Id' => ?VISITED_PLMN_001_01,
               'Requested-EUTRAN-Authentication-Info' => [#{'Number-Of-Requested-Vectors' => [1]}]}].

%% AIR through handle_request emits an s6a.AIR span with command attribute
air_span(_Config) ->
    Imsi = <<"001010000000001">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
           <<"ki">> => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
           <<"opc">> => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
           <<"algorithm">> => <<"milenage">>, <<"amf">> => binary:decode_hex(<<"b9b9">>),
           <<"sqn">> => 0}),
    udr_otel_pid_exporter:capture_to(self()),
    {reply, ['AIA' | _]} =
        udr_diameter_s6a:handle_request(#diameter_packet{msg = air(Imsi)}, svc,
                                        {make_ref(), caps()}),
    ?assert(received_s6a_span(<<"s6a.AIR">>, 2000)),
    ok.

received_s6a_span(Name, Timeout) ->
    receive
        {otel_span, #{name := Name} = S} ->
            ?assertEqual('AIR', maps:get('s6a.command', maps:get(attributes, S))),
            true;
        {otel_span, _Other} -> received_s6a_span(Name, Timeout)
    after Timeout -> false
    end.
