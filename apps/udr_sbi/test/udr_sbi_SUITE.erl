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
-module(udr_sbi_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([ue_imsi/1, strip_meta/1, auth_view/1,
         listener_up/1, read_resources/1,
         registration_write/1, registration_write_bad_json/1,
         registration_write_storage_error/1]).

-define(PORT, 18080).

all() ->
    [ue_imsi, strip_meta, auth_view,
     listener_up, read_resources,
     registration_write, registration_write_bad_json,
     registration_write_storage_error].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    application:load(udr_sbi),
    application:set_env(udr_sbi, port, ?PORT),
    %% udr_sbi calls opentelemetry_cowboy_experimental_h:init/0 on start, which
    %% registers histograms on the global meter provider (otel_meter_provider_global).
    %% In a full `rebar3 ct` run the OTEL SDK may have been started and stopped by a
    %% prior suite (e.g. udr_otel_SUITE), leaving a stale persistent_term meter entry
    %% pointing at a dead gen_server.  Start opentelemetry_experimental here so the
    %% provider is alive before the SBI listener registers its instruments.
    {ok, S0} = application:ensure_all_started(opentelemetry_experimental),
    {ok, S1} = application:ensure_all_started(udr_sbi),
    {ok, _}  = application:ensure_all_started(inets),
    [{started, lists:usort(S0 ++ S1)} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    udr_db_ct:teardown_mnesia(),
    ok.

url(Path) -> "http://127.0.0.1:" ++ integer_to_list(?PORT) ++ Path.

req(get, Path)    -> httpc:request(get, {url(Path), []}, [], [{body_format, binary}]);
req(delete, Path) -> httpc:request(delete, {url(Path), []}, [], [{body_format, binary}]).
req(put, Path, Body) -> httpc:request(put, {url(Path), [], "application/json", Body}, [], [{body_format, binary}]).

ue_imsi(_Config) ->
    ?assertEqual({ok, <<"001010000000001">>}, udr_sbi:ue_imsi(<<"imsi-001010000000001">>)),
    ?assertEqual(error, udr_sbi:ue_imsi(<<"001010000000001">>)),
    ?assertEqual(error, udr_sbi:ue_imsi(<<"imsi-">>)),
    ok.

strip_meta(_Config) ->
    ?assertEqual(#{<<"a">> => 1},
                 udr_sbi:strip_meta(#{<<"a">> => 1, <<"version">> => 3, <<"_id">> => <<"k">>})),
    ok.

auth_view(_Config) ->
    V = udr_sbi:auth_view(#{<<"ki">> => <<1,2,255>>, <<"opc">> => <<3,4>>,
                            <<"amf">> => <<16#b9,16#b9>>, <<"algorithm">> => <<"milenage">>,
                            <<"sqn">> => 7, <<"version">> => 9}),
    ?assertEqual(<<"0102ff">>, maps:get(<<"ki">>, V)),
    ?assertEqual(<<"b9b9">>, maps:get(<<"amf">>, V)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, V)),
    ?assertEqual(7, maps:get(<<"sqn">>, V)),
    ?assertEqual(error, maps:find(<<"version">>, V)),
    ok.

%% the SBI listener answers on a routed path
listener_up(_Config) ->
    {ok, {{_, Status, _}, _, _}} =
        req(get, "/nudr-dr/v1/subscription-data/imsi-1/authentication-data/authentication-subscription"),
    ?assert(is_integer(Status)),
    ok.

%% GET auth (hex), am-data (AM/SM split), registration; plus 404 and 400
read_resources(_Config) ->
    Imsi = <<"001010000000001">>,
    U = "/nudr-dr/v1/subscription-data/imsi-" ++ binary_to_list(Imsi),
    ok = udr_data:put_authentication_subscription(Imsi,
           #{<<"ki">> => <<1,2,255>>, <<"opc">> => <<3,4>>, <<"amf">> => <<16#b9,16#b9>>,
             <<"algorithm">> => <<"milenage">>, <<"sqn">> => 0}),
    ok = udr_data:put_subscription_data(Imsi,
           #{<<"msisdn">> => <<"49170">>,
             <<"apn_config_profile">> => #{<<"context_id">> => 1}}),
    ok = udr_data:put_3gpp_access_registration(Imsi,
           #{<<"mme_host">> => <<"mme-a">>, <<"mme_realm">> => <<"epc">>}),

    {ok, {{_, 200, _}, _, AB}} = req(get, U ++ "/authentication-data/authentication-subscription"),
    Auth = udr_sbi_json:decode(AB),
    ?assertEqual(<<"0102ff">>, maps:get(<<"ki">>, Auth)),
    ?assertEqual(error, maps:find(<<"version">>, Auth)),

    {ok, {{_, 200, _}, _, AMB}} = req(get, U ++ "/provisioned-data/am-data"),
    Am = udr_sbi_json:decode(AMB),
    ?assertEqual(<<"49170">>, maps:get(<<"msisdn">>, Am)),
    ?assertEqual(error, maps:find(<<"apn_config_profile">>, Am)),   %% AM excludes SM data

    {ok, {{_, 200, _}, _, RB}} = req(get, U ++ "/context-data/amf-3gpp-access"),
    ?assertEqual(<<"mme-a">>, maps:get(<<"mme_host">>, udr_sbi_json:decode(RB))),

    {ok, {{_, 404, _}, _, _}} = req(get,
        "/nudr-dr/v1/subscription-data/imsi-999/authentication-data/authentication-subscription"),
    {ok, {{_, 404, _}, _, _}} = req(get,
        "/nudr-dr/v1/subscription-data/imsi-999/context-data/amf-3gpp-access"),
    {ok, {{_, 400, _}, _, _}} = req(get,
        "/nudr-dr/v1/subscription-data/bad-id/provisioned-data/am-data"),
    ok.

%% PUT registration stores it (GET shows it); DELETE removes it (GET 404)
registration_write(_Config) ->
    U = "/nudr-dr/v1/subscription-data/imsi-001010000000002/context-data/amf-3gpp-access",
    Body = udr_sbi_json:encode(#{<<"mme_host">> => <<"mme-b">>, <<"mme_realm">> => <<"epc">>}),
    {ok, {{_, 204, _}, _, _}} = req(put, U, Body),
    {ok, {{_, 200, _}, _, RB}} = req(get, U),
    ?assertEqual(<<"mme-b">>, maps:get(<<"mme_host">>, udr_sbi_json:decode(RB))),
    {ok, {{_, 204, _}, _, _}} = req(delete, U),
    {ok, {{_, 404, _}, _, _}} = req(get, U),
    ok.

%% PUT with invalid JSON returns 400 problem+json
registration_write_bad_json(_Config) ->
    U = "/nudr-dr/v1/subscription-data/imsi-3/context-data/amf-3gpp-access",
    {ok, {{_, 400, _}, Hdrs, _}} = req(put, U, <<"{bad json">>),
    ?assertEqual("application/problem+json", proplists:get_value("content-type", Hdrs)),
    ok.

%% A backend write failure (valid JSON body) must surface as 500, distinct from
%% the 400 returned for a malformed body. Force the write to fail.
registration_write_storage_error(_Config) ->
    Restore = persistent_term:get({udr_db, backend}, udr_db_mnesia),
    persistent_term:put({udr_db, backend}, udr_db_failing_backend),
    try
        U = "/nudr-dr/v1/subscription-data/imsi-001010000000099/context-data/amf-3gpp-access",
        Body = udr_sbi_json:encode(#{<<"mme_host">> => <<"mme-x">>, <<"mme_realm">> => <<"epc">>}),
        {ok, {{_, 500, _}, _, _}} = req(put, U, Body)
    after
        persistent_term:put({udr_db, backend}, Restore)
    end,
    ok.
