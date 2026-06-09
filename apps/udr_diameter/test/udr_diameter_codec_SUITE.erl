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
-module(udr_diameter_codec_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("diameter/include/diameter.hrl").

-define(DICT, diameter_3gpp_s6a).
-define(OPTS, #{string_decode => false, decode_format => map}).

-export([all/0]).
-export([air_decode/1, air_decode_resync/1, air_decode_default_numvectors/1,
         ulr_decode/1, ulr_decode_flags/1, pur_decode/1, encode_air_answer/1,
         encode_error_user_unknown/1, encode_error_unable/1,
         encode_ulr_answer/1, encode_ulr_answer_skip/1, encode_pua_answer/1,
         encode_pua_answer_freeze/1, clr_request/1,
         ula_roundtrip/1, clr_roundtrip/1, aia_answer_roundtrip/1]).

all() ->
    [air_decode, air_decode_resync, air_decode_default_numvectors,
     ulr_decode, ulr_decode_flags, pur_decode, encode_air_answer,
     encode_error_user_unknown, encode_error_unable,
     encode_ulr_answer, encode_ulr_answer_skip, encode_pua_answer,
     encode_pua_answer_freeze, clr_request,
     ula_roundtrip, clr_roundtrip, aia_answer_roundtrip].

air_decode(_Config) ->
    Req = #{'User-Name' => <<"001010000000001">>,
            'Visited-PLMN-Id' => <<0,16#f1,16#10>>,
            'Requested-EUTRAN-Authentication-Info' =>
                [#{'Number-Of-Requested-Vectors' => [3]}]},
    ?assertEqual(#{imsi => <<"001010000000001">>,
                   visited_plmn => <<0,16#f1,16#10>>,
                   num_vectors => 3,
                   resync => undefined},
                 udr_diameter_codec:decode_air(Req)),
    ok.

air_decode_resync(_Config) ->
    Resync = <<255,254,253,252,251,250,0,0,0,0,0,0,0,0,0,0,
               1,2,3,4,5,6,7,8,9,10,11,12,13,14>>,   %% 16 + 14 = 30 bytes
    Req = #{'User-Name' => <<"i">>, 'Visited-PLMN-Id' => <<0,0,0>>,
            'Requested-EUTRAN-Authentication-Info' =>
                [#{'Number-Of-Requested-Vectors' => [1],
                   'Re-Synchronization-Info' => [Resync]}]},
    #{resync := {Rand, Auts}} = udr_diameter_codec:decode_air(Req),
    ?assertEqual(16, byte_size(Rand)),
    ?assertEqual(14, byte_size(Auts)),
    ok.

air_decode_default_numvectors(_Config) ->
    %% No Requested-EUTRAN-Authentication-Info -> default to 1 vector, no resync.
    Req = #{'User-Name' => <<"i">>, 'Visited-PLMN-Id' => <<0,0,0>>},
    ?assertEqual(#{imsi => <<"i">>, visited_plmn => <<0,0,0>>,
                   num_vectors => 1, resync => undefined},
                 udr_diameter_codec:decode_air(Req)),
    ok.

ulr_decode(_Config) ->
    Req = #{'User-Name' => <<"i">>, 'Origin-Host' => <<"mme-a">>,
            'Origin-Realm' => <<"epc">>, 'RAT-Type' => 1004,
            'Visited-PLMN-Id' => <<0,16#f1,16#10>>},
    ?assertEqual(#{imsi => <<"i">>, mme_host => <<"mme-a">>, mme_realm => <<"epc">>,
                   rat_type => 1004, visited_plmn => <<0,16#f1,16#10>>,
                   ulr_flags => 0, skip_subscriber_data => false, initial_attach => false},
                 udr_diameter_codec:decode_ulr(Req)),
    ok.

ulr_decode_flags(_Config) ->
    %% Skip-Subscriber-Data (bit 2 = 4) and Initial-Attach (bit 5 = 32) both set = 36.
    Req = #{'User-Name' => <<"i">>, 'Origin-Host' => <<"m">>, 'Origin-Realm' => <<"r">>,
            'RAT-Type' => 1004, 'Visited-PLMN-Id' => <<0,0,0>>, 'ULR-Flags' => 36},
    D = udr_diameter_codec:decode_ulr(Req),
    ?assertEqual(36, maps:get(ulr_flags, D)),
    ?assertEqual(true, maps:get(skip_subscriber_data, D)),
    ?assertEqual(true, maps:get(initial_attach, D)),
    ok.

pur_decode(_Config) ->
    ?assertEqual(#{imsi => <<"i">>, mme_host => <<"mme-a">>},
                 udr_diameter_codec:decode_pur(#{'User-Name' => <<"i">>,
                                                 'Origin-Host' => <<"mme-a">>})),
    ok.

encode_air_answer(_Config) ->
    Vs = [#{rand => <<0:128>>, xres => <<1:64>>, autn => <<2:128>>, kasme => <<3:256>>},
          #{rand => <<4:128>>, xres => <<5:64>>, autn => <<6:128>>, kasme => <<7:256>>}],
    Avps = udr_diameter_codec:encode_air_answer({ok, #{vectors => Vs}}),
    ?assertEqual([2001], maps:get('Result-Code', Avps)),
    [#{'E-UTRAN-Vector' := EVs}] = maps:get('Authentication-Info', Avps),
    ?assertEqual(2, length(EVs)),
    ?assertEqual(<<0:128>>, maps:get('RAND', hd(EVs))),
    ok.

encode_error_user_unknown(_Config) ->
    Avps = udr_diameter_codec:encode_air_answer({error, user_unknown}),
    ?assertEqual([#{'Vendor-Id' => 10415, 'Experimental-Result-Code' => 5001}],
                 maps:get('Experimental-Result', Avps)),
    ?assertEqual(error, maps:find('Result-Code', Avps)),
    ok.

encode_error_unable(_Config) ->
    Avps = udr_diameter_codec:encode_air_answer({error, session_busy}),
    ?assertEqual([5012], maps:get('Result-Code', Avps)),
    ok.

encode_ulr_answer(_Config) ->
    Profile = #{<<"ambr">> => #{<<"ul">> => 1000, <<"dl">> => 2000},
                <<"apn_config_profile">> => #{<<"context_id">> => 1}},
    Avps = udr_diameter_codec:encode_ulr_answer({ok, #{subscription_data => Profile}}),
    ?assertEqual([2001], maps:get('Result-Code', Avps)),
    [SD] = maps:get('Subscription-Data', Avps),
    [#{'Max-Requested-Bandwidth-UL' := 1000}] = maps:get('AMBR', SD),
    ok.

encode_ulr_answer_skip(_Config) ->
    %% Skip-Subscriber-Data: handler returns an answer with no subscription_data key.
    Avps = udr_diameter_codec:encode_ulr_answer({ok, #{}}),
    ?assertEqual([2001], maps:get('Result-Code', Avps)),
    ?assertEqual([1], maps:get('ULA-Flags', Avps)),
    ?assertEqual(error, maps:find('Subscription-Data', Avps)),
    ok.

encode_pua_answer(_Config) ->
    Avps = udr_diameter_codec:encode_pua_answer({ok, #{freeze_m_tmsi => false}}),
    ?assertEqual([2001], maps:get('Result-Code', Avps)),
    ?assertEqual([0], maps:get('PUA-Flags', Avps)),
    ok.

encode_pua_answer_freeze(_Config) ->
    Avps = udr_diameter_codec:encode_pua_answer({ok, #{freeze_m_tmsi => true}}),
    ?assertEqual([2001], maps:get('Result-Code', Avps)),
    ?assertEqual([1], maps:get('PUA-Flags', Avps)),   %% bit 0 = Freeze M-TMSI
    ok.

clr_request(_Config) ->
    %% Default (no cancellation_type) -> MME Update Procedure (0).
    Def = udr_diameter_codec:clr_request(#{imsi => <<"i">>, mme_host => <<"mme-a">>,
                                           mme_realm => <<"epc">>}),
    ?assertEqual(<<"i">>, maps:get('User-Name', Def)),
    ?assertEqual(<<"mme-a">>, maps:get('Destination-Host', Def)),
    ?assertEqual(<<"epc">>, maps:get('Destination-Realm', Def)),
    ?assertEqual(0, maps:get('Cancellation-Type', Def)),
    %% Explicit initial attach -> 4; subscription withdrawal -> 2.
    Ia = udr_diameter_codec:clr_request(#{imsi => <<"i">>, mme_host => <<"m">>,
                                          mme_realm => <<"r">>,
                                          cancellation_type => initial_attach_procedure}),
    ?assertEqual(4, maps:get('Cancellation-Type', Ia)),
    Sw = udr_diameter_codec:clr_request(#{imsi => <<"i">>, mme_host => <<"m">>,
                                          mme_realm => <<"r">>,
                                          cancellation_type => subscription_withdrawal}),
    ?assertEqual(2, maps:get('Cancellation-Type', Sw)),
    ok.

%% ---------------------------------------------------------------------------
%% Round-trip tests: encode via the real dictionary, decode back, assert nested
%% fields survive. These fail at encode time if any AVP arity is wrong.
%% ---------------------------------------------------------------------------

roundtrip(Name, AnswerAvps) ->
    Common = #{'Session-Id' => <<"s1">>, 'Auth-Session-State' => 1,
               'Origin-Host' => <<"hss.example.org">>, 'Origin-Realm' => <<"example.org">>},
    Msg = [Name | maps:merge(Common, AnswerAvps)],
    Hdr = #diameter_header{version = 1, end_to_end_id = 1, hop_by_hop_id = 1},
    #diameter_packet{bin = Bin} =
        diameter_codec:encode(?DICT, #diameter_packet{header = Hdr, msg = Msg}),
    #diameter_packet{msg = [Name | Decoded]} = diameter_codec:decode(?DICT, ?OPTS, Bin),
    Decoded.

ula_roundtrip(_Config) ->
    Profile = #{<<"ambr">> => #{<<"ul">> => 1000, <<"dl">> => 2000},
                <<"apn_config_profile">> => #{<<"context_id">> => 7}},
    Ans = udr_diameter_codec:encode_ulr_answer({ok, #{subscription_data => Profile}}),
    Decoded = roundtrip('ULA', Ans),
    [SD] = maps:get('Subscription-Data', Decoded),
    [#{'Max-Requested-Bandwidth-UL' := 1000}] = maps:get('AMBR', SD),
    [#{'Context-Identifier' := 7}] = maps:get('APN-Configuration-Profile', SD),
    ok.

clr_roundtrip(_Config) ->
    Common = #{'Session-Id' => <<"s1">>, 'Auth-Session-State' => 1,
               'Origin-Host' => <<"hss">>, 'Origin-Realm' => <<"r">>},
    Clr = udr_diameter_codec:clr_request(#{imsi => <<"001010000000001">>,
                                           mme_host => <<"mme-a">>, mme_realm => <<"epc">>}),
    Msg = ['CLR' | maps:merge(Common#{'Destination-Realm' => <<"epc">>}, Clr)],
    Hdr = #diameter_header{version = 1, end_to_end_id = 1, hop_by_hop_id = 1, is_request = true},
    #diameter_packet{bin = Bin} =
        diameter_codec:encode(?DICT, #diameter_packet{header = Hdr, msg = Msg}),
    #diameter_packet{msg = ['CLR' | Decoded]} = diameter_codec:decode(?DICT, ?OPTS, Bin),
    ?assertEqual(<<"001010000000001">>, maps:get('User-Name', Decoded)),
    ?assertEqual(<<"mme-a">>, maps:get('Destination-Host', Decoded)),
    ?assertEqual(0, maps:get('Cancellation-Type', Decoded)),
    ok.

aia_answer_roundtrip(_Config) ->
    Vs = [#{rand => <<0:128>>, xres => <<1:64>>, autn => <<2:128>>, kasme => <<3:256>>}],
    Ans = udr_diameter_codec:encode_air_answer({ok, #{vectors => Vs}}),
    Decoded = roundtrip('AIA', Ans),
    [#{'E-UTRAN-Vector' := [V]}] = maps:get('Authentication-Info', Decoded),
    ?assertEqual(<<0:128>>, maps:get('RAND', V)),
    ?assertEqual(<<3:256>>, maps:get('KASME', V)),
    ok.
