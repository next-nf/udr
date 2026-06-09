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
-module(udr_diameter_s6a_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("diameter/include/diameter_gen_base_rfc6733.hrl").
-include_lib("udr_diameter/include/s6a_result_codes.hrl").
-include("s6a_test.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([air_yields_aia_two_vectors/1, air_unknown_imsi_experimental_5001/1]).

all() ->
    [air_yields_aia_two_vectors, air_unknown_imsi_experimental_5001].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    ok.

caps() ->
    #diameter_caps{origin_host = {<<"hss.local">>, <<"mme.local">>},
                   origin_realm = {<<"local">>, <<"local">>}}.

air(Imsi) ->
    ['AIR' | #{'Session-Id' => <<"s1">>, 'Auth-Session-State' => 1,
               'Origin-Host' => <<"mme.local">>, 'Origin-Realm' => <<"local">>,
               'Destination-Realm' => <<"local">>, 'User-Name' => Imsi,
               'Visited-PLMN-Id' => ?VISITED_PLMN_001_01,
               'Requested-EUTRAN-Authentication-Info' =>
                   [#{'Number-Of-Requested-Vectors' => [2]}]}].

air_yields_aia_two_vectors(_Config) ->
    Imsi = <<"001010000000001">>,
    ok = udr_data:put_authentication_subscription(Imsi, #{
           <<"ki">> => binary:decode_hex(<<"465b5ce8b199b49faa5f0a2ee238a6bc">>),
           <<"opc">> => binary:decode_hex(<<"cd63cb71954a9f4e48a5994e37a02baf">>),
           <<"algorithm">> => <<"milenage">>,
           <<"amf">> => binary:decode_hex(<<"b9b9">>), <<"sqn">> => 0}),
    {reply, ['AIA' | Ans]} =
        udr_diameter_s6a:handle_request(#diameter_packet{msg = air(Imsi)}, svc,
                                        {make_ref(), caps()}),
    ?assertEqual([?'DIAMETER_BASE_RESULT-CODE_SUCCESS'], maps:get('Result-Code', Ans)),
    ?assertEqual(<<"s1">>, maps:get('Session-Id', Ans)),
    [#{'E-UTRAN-Vector' := EVs}] = maps:get('Authentication-Info', Ans),
    ?assertEqual(2, length(EVs)),
    ok.

air_unknown_imsi_experimental_5001(_Config) ->
    {reply, ['AIA' | Ans]} =
        udr_diameter_s6a:handle_request(#diameter_packet{msg = air(<<"nope">>)}, svc,
                                        {make_ref(), caps()}),
    ?assertEqual([#{'Vendor-Id' => ?VENDOR_ID_3GPP,
                    'Experimental-Result-Code' => ?DIAMETER_ERROR_USER_UNKNOWN}],
                 maps:get('Experimental-Result', Ans)),
    ok.
