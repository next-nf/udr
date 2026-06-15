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
-module(udr_hss_integration_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("udr_hss_test.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([s6a_core_attach/1]).

all() -> [s6a_core_attach].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [ application:stop(A) || A <- lists:reverse(Started) ],
    ok.

s6a_core_attach(_Config) ->
    Imsi = <<"001010000000099">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
           <<"ki">> => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
           <<"opc">> => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
           <<"algorithm">> => <<"milenage">>,
           <<"amf">> => binary:decode_hex(<<"b9b9">>), <<"sqn">> => 0}),
    ok = udr_data:put_subscription_data(Imsi, #{<<"msisdn">> => <<"49170">>,
           <<"apn_config_profile">> => #{<<"context_id">> => 1}}),
    Plmn = ?VISITED_PLMN_001_01,
    {ok, #{vectors := Vs}, []} =
        udr_hss:handle_air(#{imsi => Imsi, visited_plmn => Plmn, num_vectors => 3}),
    ?assertEqual(3, length(Vs)),
    U1 = #{imsi => Imsi, mme_host => <<"mme-a">>, mme_realm => <<"epc">>,
           rat_type => eutran, visited_plmn => Plmn},
    {ok, #{subscription_data := _}, []} = udr_hss:handle_ulr(U1),
    U2 = U1#{mme_host => <<"mme-b">>},
    {ok, _, [{cancel_location, #{mme_host := <<"mme-a">>}}]} = udr_hss:handle_ulr(U2),
    {ok, #{freeze_m_tmsi := true}, []} =
        udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-b">>}),
    {ok, PReg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(true, maps:get(<<"ue_purged">>, PReg)),
    ok.
