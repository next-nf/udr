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

-export([all/0]).
-export([aia_roundtrip/1]).

all() -> [aia_roundtrip].

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
