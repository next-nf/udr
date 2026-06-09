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
-module(udr_hss_resync_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("udr_hss_test.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([air_valid_auts_repairs_sqn/1]).

-define(KI,  binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>)).
-define(OPC, binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>)).

all() -> [air_valid_auts_repairs_sqn].

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    Started = ?config(started, Config),
    [ application:stop(A) || A <- lists:reverse(Started) ],
    ok.

air_valid_auts_repairs_sqn(_Config) ->
    Imsi = <<"001010000000002">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
           <<"ki">> => ?KI, <<"opc">> => ?OPC,
           <<"algorithm">> => <<"milenage">>,
           <<"amf">> => binary:decode_hex(<<"b9b9">>),
           <<"sqn">> => 9000}),
    Rand   = binary:decode_hex(<<"23553cbe9637a89d218ae64dae47bf35">>),
    SqnMs  = <<16#000000010000:48>>,
    AkStar = udr_crypto_milenage:f5star(?KI, ?OPC, Rand),
    Conc   = crypto:exor(SqnMs, AkStar),
    MacS   = udr_crypto_milenage:f1star(?KI, ?OPC, Rand, SqnMs, <<0:16>>),
    Auts   = <<Conc/binary, MacS/binary>>,
    {ok, _Ans, []} = udr_hss:handle_air(#{imsi => Imsi,
                                          visited_plmn => ?VISITED_PLMN_001_01,
                                          num_vectors => 1,
                                          resync => {Rand, Auts}}),
    {ok, Auth} = udr_data:get_authentication_subscription(Imsi),
    ?assertEqual(16#000000010000 + 1 + 1, maps:get(<<"sqn">>, Auth)),
    ok.
