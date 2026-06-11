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
-module(udr_diameter_dict_SUITE).
-moduledoc "Common Test codec round-trip tests for the diameter_3gpp_s6a dictionary.".

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("diameter/include/diameter.hrl").
-include_lib("udr_diameter/include/diameter_3gpp_s6a.hrl").

-export([all/0]).
-export([aia_roundtrip/1, open5gs_ulr_decodes_clean/1]).

all() -> [aia_roundtrip, open5gs_ulr_decodes_clean].

%% ---------------------------------------------------------------------------
%% Tests
%% ---------------------------------------------------------------------------

-doc "Encode an AIA carrying one E-UTRAN-Vector then decode in map format and assert
the round-trip is lossless for Session-Id, RAND and KASME.".
aia_roundtrip(_Config) ->
    Dict = diameter_3gpp_s6a,
    %% Build the E-UTRAN-Vector in map format.
    %%   E-UTRAN-Vector has required AVPs: RAND, XRES, AUTN, KASME; optional: Item-Number.
    Vector = #{'RAND'  => <<0:128>>,
               'XRES'  => <<1:64>>,
               'AUTN'  => <<2:128>>,
               'KASME' => <<3:256>>},
    %% AIA message in [MsgName | Map] list form.
    %%   Required: Auth-Session-State, Origin-Host, Origin-Realm.
    %%   Optional: Session-Id (fixed <> in grammar), Result-Code, Authentication-Info.
    Msg = ['AIA' | #{'Session-Id'          => <<"sess-1">>,
                     'Result-Code'         => [2001],
                     'Auth-Session-State'  => 1,
                     'Origin-Host'         => <<"hss.example.org">>,
                     'Origin-Realm'        => <<"example.org">>,
                     'Authentication-Info' => [#{'E-UTRAN-Vector' => [Vector]}]}],
    %% Provide a minimal Diameter header (version + ids).
    Hdr = #diameter_header{version        = 1,
                           end_to_end_id  = 42,
                           hop_by_hop_id  = 43},
    %% Encode to a wire binary.
    %% diameter_codec:encode/2  =>  encode(Mod, Pkt | Msg)
    #diameter_packet{bin = Bin} =
        diameter_codec:encode(Dict, #diameter_packet{header = Hdr, msg = Msg}),
    ?assert(is_binary(Bin)),
    %% Decode back with map-format option.
    %% diameter_codec:decode/3  =>  decode(Mod, Opts, Pkt | Bin)
    Opts = #{string_decode => false, decode_format => map},
    #diameter_packet{msg = ['AIA' | Decoded]} =
        diameter_codec:decode(Dict, Opts, Bin),
    ?assert(is_map(Decoded)),
    %% Session-Id round-trip.
    ?assertEqual(<<"sess-1">>, maps:get('Session-Id', Decoded)),
    %% Drill into nested map: Authentication-Info -> E-UTRAN-Vector.
    [AuthInfo] = maps:get('Authentication-Info', Decoded),
    ?assert(is_map(AuthInfo)),
    [DecodedVector] = maps:get('E-UTRAN-Vector', AuthInfo),
    ?assert(is_map(DecodedVector)),
    ?assertEqual(<<0:128>>, maps:get('RAND',  DecodedVector)),
    ?assertEqual(<<3:256>>, maps:get('KASME', DecodedVector)),
    ok.

-doc "Decode the real Open5GS S6a Update-Location-Request captured during an srsRAN
attach (demos/srsran-attach/s6a-air.pcap, frame 9) and assert it decodes cleanly.
Open5GS includes Terminal-Information (IMEI + Software-Version) and
UE-SRVCC-Capability; these were absent from the dictionary, so the real ULR decoded
with errors (5001 AVP_UNSUPPORTED on 1401, 5008 AVP_NOT_ALLOWED on 1615) and crashed
the HSS request process -- the actual cause of the failed attach (the AIR, contrary
to the original report, decodes and answers fine).".
open5gs_ulr_decodes_clean(_Config) ->
    %% Verbatim tcp.payload of the captured ULR (command 316, S6a).
    Hex =
          "0100013cc000013c0100002341dbbb735413fba2000001074000002b6d6d652e"
          "6f70656e766572736f3b313738303938373230313b32303b6170705f73366100"
          "000001154000000c0000000100000108400000156d6d652e6f70656e76657273"
          "6f00000000000128400000116f70656e766572736f0000000000011b40000011"
          "6f70656e766572736f0000000000000140000017323038393630313030303030"
          "3030310000000579c0000038000028af0000057ac000001a000028af33353334"
          "3930303639383733333100000000057bc000000e000028af3533000000000408"
          "80000010000028af000003ec0000057dc0000010000028af000000020000057f"
          "c000000f000028af02f869000000064f80000010000028af0000000000000104"
          "400000200000010a4000000c000028af000001024000000c01000023",
    Bin = hex_to_bin(Hex),
    Hdr = diameter_codec:decode_header(Bin),
    Opts = #{string_decode => false, decode_format => map},
    #diameter_packet{msg = Msg, errors = Errors} =
        diameter_codec:decode(diameter_3gpp_s6a, Opts,
                              #diameter_packet{header = Hdr, bin = Bin}),
    ?assertEqual([], Errors),
    ['ULR' | Map] = Msg,
    ?assertEqual(?'S6A_RAT-TYPE_EUTRAN', maps:get('RAT-Type', Map)),
    [TermInfo] = maps:get('Terminal-Information', Map),
    ?assertEqual([<<"35349006987331">>], maps:get('IMEI', TermInfo)),
    ?assertMatch([_], maps:get('UE-SRVCC-Capability', Map)),
    ok.

%% "0a1b" -> <<10, 27>>
hex_to_bin(Hex) ->
    << <<(list_to_integer([A, B], 16))>> || <<A, B>> <= list_to_binary(Hex) >>.
