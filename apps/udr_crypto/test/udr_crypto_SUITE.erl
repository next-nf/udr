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
-module(udr_crypto_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-import_record(udr_crypto, [eps_av]).
-export([all/0]).
-export([eps_vector_set1/1, generate_vectors/1, resync_roundtrip/1, opc_dispatch/1,
         eps_vector_tuak/1]).

-define(H(S), binary:decode_hex(<<S>>)).

all() -> [eps_vector_set1, generate_vectors, resync_roundtrip, opc_dispatch,
          eps_vector_tuak].

%% End-to-end EPS vector for MILENAGE Set 1, SN-id 00f110.
%%   XRES = RES = a54211d5e3ba50bf
%%   AK = aa689c648370 ; SQN = ff9bb4d0b607 ; SQN XOR AK = 55f328b43577
%%   AUTN = (SQN XOR AK) ‖ AMF ‖ MAC-A = 55f328b43577 b9b9 4a9ffac354dfafb3
eps_vector_set1(_Config) ->
    V = udr_crypto:eps_vector(milenage,
                              ?H("465b5ce8b199b49faa5f0a2ee238a6bc"),  %% K
                              ?H("cd63cb71954a9f4e48a5994e37a02baf"),  %% OPc
                              ?H("b9b9"),                              %% AMF
                              ?H("ff9bb4d0b607"),                      %% SQN
                              ?H("23553cbe9637a89d218ae64dae47bf35"),  %% RAND
                              ?H("00f110")),                           %% SN-id
    ?assertEqual(?H("23553cbe9637a89d218ae64dae47bf35"), V#eps_av.rand),
    ?assertEqual(?H("a54211d5e3ba50bf"),                 V#eps_av.xres),
    ?assertEqual(?H("55f328b43577b9b94a9ffac354dfafb3"), V#eps_av.autn),
    ?assertEqual(32, byte_size(V#eps_av.kasme)),
    ok.

generate_vectors(_Config) ->
    K   = ?H("465b5ce8b199b49faa5f0a2ee238a6bc"),
    OPc = ?H("cd63cb71954a9f4e48a5994e37a02baf"),
    AMF = ?H("b9b9"),
    Sqn0 = 1000,
    {Vs, Sqn1} = udr_crypto:generate_eps_vectors(milenage, K, OPc, AMF, Sqn0, 3,
                                                 ?H("00f110")),
    ?assertEqual(3, length(Vs)),
    ?assertEqual(Sqn0 + 3, Sqn1),
    %% Each vector has a distinct, 16-byte random RAND.
    Rands = [V#eps_av.rand || V <- Vs],
    ?assertEqual(3, length(lists:usort(Rands))),
    ?assert(lists:all(fun(R) -> byte_size(R) =:= 16 end, Rands)),
    ok.

resync_roundtrip(_Config) ->
    K   = ?H("465b5ce8b199b49faa5f0a2ee238a6bc"),
    OPc = ?H("cd63cb71954a9f4e48a5994e37a02baf"),
    RAND= ?H("23553cbe9637a89d218ae64dae47bf35"),
    SqnMs = <<16#00000001AAAA:48>>,
    %% Build AUTS as the UE does: AK* = f5*, conceal SQN_MS, MAC-S with AMF=0000.
    AkStar = udr_crypto_milenage:f5star(K, OPc, RAND),
    Conc   = crypto:exor(SqnMs, AkStar),
    MacS   = udr_crypto_milenage:f1star(K, OPc, RAND, SqnMs, <<0:16>>),
    AUTS   = <<Conc/binary, MacS/binary>>,
    ?assertEqual({ok, SqnMs}, udr_crypto:verify_resync(milenage, K, OPc, RAND, AUTS)),
    %% Corrupt the MAC-S -> rejection.
    Bad = <<Conc/binary, (crypto:exor(MacS, <<1, 0,0,0,0,0,0,0>>))/binary>>,
    ?assertEqual({error, mac_failure},
                 udr_crypto:verify_resync(milenage, K, OPc, RAND, Bad)),
    ok.

opc_dispatch(_Config) ->
    %% Public facade dispatches OPc derivation to the selected algorithm (MILENAGE Set 1).
    ?assertEqual(?H("cd63cb71954a9f4e48a5994e37a02baf"),
                 udr_crypto:opc(milenage,
                                ?H("465b5ce8b199b49faa5f0a2ee238a6bc"),
                                ?H("cdc202d5123e20f62b6d676ac72cb318"))),
    ok.

%% End-to-end EPS vector through udr_crypto for TUAK (TS 35.233 Set 1 inputs).
%% Expected values are derived from the low-level TUAK functions rather than
%% hardcoded — TS 35.233 Set 1 RES is the 32-bit UMTS profile output (657acd64),
%% whereas the EPS profile always yields 64-bit f2.
eps_vector_tuak(_Config) ->
    K    = ?H("abababababababababababababababab"),
    TOP  = ?H("5555555555555555555555555555555555555555555555555555555555555555"),
    RAND = ?H("42424242424242424242424242424242"),
    AMF  = ?H("ffff"),
    SQN  = ?H("111111111111"),
    SnId = <<1, 1, 1>>,
    TOPc = udr_crypto_tuak:topc_gen(K, TOP, 1),
    V = udr_crypto:eps_vector(tuak, K, TOPc, AMF, SQN, RAND, SnId),
    %% AUTN = (SQN XOR AK) ++ AMF ++ MAC-A; trailing 8 bytes are MAC-A.
    <<_SqnXorAk:6/binary, _Amf:2/binary, MacA:8/binary>> = V#eps_av.autn,
    ExpectedMacA = udr_crypto_tuak:f1(K, TOPc, RAND, SQN, AMF),
    ExpectedXres = udr_crypto_tuak:f2(K, TOPc, RAND),
    ?assertEqual(ExpectedMacA, MacA),
    ?assertEqual(ExpectedXres, V#eps_av.xres),
    ?assertEqual(16, byte_size(V#eps_av.rand)),
    ?assertEqual(16, byte_size(V#eps_av.autn)),
    ?assertEqual(32, byte_size(V#eps_av.kasme)),
    ok.
