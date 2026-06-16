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

-module(udr_crypto_tuak_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0]).
-export([topc/1, mac/1, f2345/1, f5star/1]).

-define(H(S), binary:decode_hex(iolist_to_binary(S))).

%% sets() -> [{Name,K,RAND,SQN,AMF,TOP,Iters,TOPc,MACA,MACS,RES,CK,IK,AK,F5S}]
sets() ->
  [{"Set1",
    "abababababababababababababababab",
    "42424242424242424242424242424242",
    "111111111111","ffff",
    "5555555555555555555555555555555555555555555555555555555555555555",
    1,
    "bd04d9530e87513c5d837ac2ad954623a8e2330c115305a73eb45d1f40cccbff",
    "f9a54e6aeaa8618d","e94b4dc6c7297df3","657acd64",
    "d71a1e5c6caffe986a26f783e5c78be1","be849fa2564f869aecee6f62d4337e72",
    "719f1e9b9054","e7af6b3d0e38"},
   {"Set2",
    "fffefdfcfbfaf9f8f7f6f5f4f3f2f1f0efeeedecebeae9e8e7e6e5e4e3e2e1e0",
    "0123456789abcdef0123456789abcdef",
    "0123456789ab","abcd",
    "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f",
    1,
    "305425427e18c503c8a4b294ea72c95d0c36c6c6b29d0c65de5974d5977f8524",
    "c0b8c2d4148ec7aa5f1d78a97e4d1d58","ef81af7290f7842c6ceafa537fa0745b",
    "e9d749dc4eea0035",
    "a4cb6f6529ab17f8337f27baa8234d47","2274155ccf4199d5e2abcbf621907f90",
    "480a9345cc1e","f84eb338848c"},
   {"Set3",
    "fffefdfcfbfaf9f8f7f6f5f4f3f2f1f0efeeedecebeae9e8e7e6e5e4e3e2e1e0",
    "0123456789abcdef0123456789abcdef",
    "0123456789ab","abcd",
    "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f",
    1,
    "305425427e18c503c8a4b294ea72c95d0c36c6c6b29d0c65de5974d5977f8524",
    "d97b75a1776065271b1e212bc3b1bf173f438b21e6c64a55a96c372e085e5cc5",
    "427bbf07c6e3a86c54f8c5216499f3909a6fd4a164c9fe235b1550258111b821",
    "07021c73e7635c7d",
    "4d59ac796834eb85d11fa148a5058c3c","126d47500136fdc5ddfd14f19ebf16749ce4b6435323fbb5715a3a796a6082bd",
    "1d6622c4e59a","f84eb338848c"},
   {"Set4",
    "b8da837a50652d6ac7c97da14f6acc61",
    "6887e55425a966bd86c9661a5fa72be8",
    "0dea2ee2c5af","df1e",
    "0952be13556c32ebc58195d9dd930493e12a9003669988ffde5fa1f0fe35cc01",
    1,
    "2bc16eb657a68e1f446f08f57c0efb1d493527a2e652ce281eb6ca0e4487760a",
    "749214087958dd8f58bfcdf869d8ae3f","619e865afe80e382aee13063f9dfb56d",
    "4041ce438e3e38e8aa96562eed83ac43",
    "3e3bc01bea0cd914c4c2c83ce2d92757","666a8e6f577b1aa77b7fd53cebb8a3d6",
    "1f880d005119","45e617d77fe5"},
   {"Set5",
    "1574ca56881d05c189c82880f789c9cd4244955f4426aa2b69c29f15770e5aa5",
    "c570aac68cde651fb1e3088322498bef",
    "c89bb71f3a41","297d",
    "e59f6eb10ea406813f4991b0b9e02f181edf4c7e17b480f66d34da35ee88c95e",
    1,
    "3c6052e41532a28a47aa3cbb89f223e8f3aaa976aecd48bc3e7d6165a55eff62",
    "d7340dad02b4cb01","c6021e2e66accb15",
    "84d89b41db1867ffd4c7ba1d82163f4d526a20fbae5418fbb526940b1eeb905c",
    "d419676afe5ab58c1d8bee0d43523a4d2f52ef0b31a4676a0c334427a988fe65",
    "205533e505661b61d05cc0eac87818f4",
    "d7b3d2d4980a","ca9655264986"},
   {"Set6",
    "1574ca56881d05c189c82880f789c9cd4244955f4426aa2b69c29f15770e5aa5",
    "c570aac68cde651fb1e3088322498bef",
    "c89bb71f3a41","297d",
    "e59f6eb10ea406813f4991b0b9e02f181edf4c7e17b480f66d34da35ee88c95e",
    2,
    "b04a66f26c62fcd6c82de22a179ab65506ecf47f56245cd149966cfa9cec7a51",
    "90d2289ed1ca1c3dbc2247bb480d431ac71d2e4a7677f6e997cfddb0cbad88b7",
    "427355dbac30e825063aba61b556e87583abac638e3ab01c4c884ad9d458dc2f",
    "d67e6e64590d22eecba7324afa4af4460c93f01b24506d6e12047d789a94c867",
    "ede57edfc57cdffe1aae75066a1b7479bbc3837438e88d37a801cccc9f972b89",
    "48ed9299126e5057402fe01f9201cf25249f9c5c0ed2afcf084755daff1d3999",
    "6aae8d18c448","8c5f33b61f4e"}].

all() -> [topc, mac, f2345, f5star].

topc(_Config) ->
    lists:foreach(fun({Name, K, _RAND, _SQN, _AMF, TOP, Iters, TOPc, _, _, _, _, _, _, _}) ->
        Got = udr_crypto_tuak:topc_gen(?H(K), ?H(TOP), Iters),
        ?assertEqual(?H(TOPc), Got,
                     lists:flatten(io_lib:format("TOPc mismatch in ~s", [Name])))
    end, sets()).

mac(_Config) ->
    lists:foreach(fun({Name, K, RAND, SQN, AMF, TOP, Iters, _TOPc, MACA, MACS, _, _, _, _, _}) ->
        BinK = ?H(K),
        TOPc = udr_crypto_tuak:topc_gen(BinK, ?H(TOP), Iters),
        ML = byte_size(?H(MACA)),
        GotA = udr_crypto_tuak:f1_core(BinK, TOPc, ?H(RAND), ?H(SQN), ?H(AMF), ML, Iters),
        ?assertEqual(?H(MACA), GotA,
                     lists:flatten(io_lib:format("MACA mismatch in ~s", [Name]))),
        GotS = udr_crypto_tuak:f1star_core(BinK, TOPc, ?H(RAND), ?H(SQN), ?H(AMF), ML, Iters),
        ?assertEqual(?H(MACS), GotS,
                     lists:flatten(io_lib:format("MACS mismatch in ~s", [Name])))
    end, sets()),
    %% EPS profile: MAC=64 bits (8 bytes), using Set1 and Set5
    lists:foreach(fun({Name, K, RAND, SQN, AMF, TOP, Iters, _TOPc, _, _, _, _, _, _, _}) ->
        BinK = ?H(K),
        TOPc = udr_crypto_tuak:topc_gen(BinK, ?H(TOP), Iters),
        GotA = udr_crypto_tuak:f1(BinK, TOPc, ?H(RAND), ?H(SQN), ?H(AMF)),
        GotS = udr_crypto_tuak:f1star(BinK, TOPc, ?H(RAND), ?H(SQN), ?H(AMF)),
        ?assertEqual(8, byte_size(GotA),
                     lists:flatten(io_lib:format("EPS f1 length mismatch in ~s", [Name]))),
        ?assertEqual(8, byte_size(GotS),
                     lists:flatten(io_lib:format("EPS f1star length mismatch in ~s", [Name])))
    end, [hd(sets()), lists:nth(5, sets())]).

f2345(_Config) ->
    lists:foreach(fun({Name, K, RAND, _SQN, _AMF, TOP, Iters, _TOPc, _, _, RES, CK, IK, AK, _}) ->
        BinK = ?H(K),
        TOPc = udr_crypto_tuak:topc_gen(BinK, ?H(TOP), Iters),
        ResLen = byte_size(?H(RES)),
        CkLen  = byte_size(?H(CK)),
        IkLen  = byte_size(?H(IK)),
        {GotR, GotC, GotI, GotA} =
            udr_crypto_tuak:f2345_core(BinK, TOPc, ?H(RAND), {ResLen, CkLen, IkLen}, Iters),
        ?assertEqual(?H(RES), GotR,
                     lists:flatten(io_lib:format("RES mismatch in ~s", [Name]))),
        ?assertEqual(?H(CK),  GotC,
                     lists:flatten(io_lib:format("CK mismatch in ~s",  [Name]))),
        ?assertEqual(?H(IK),  GotI,
                     lists:flatten(io_lib:format("IK mismatch in ~s",  [Name]))),
        ?assertEqual(?H(AK),  GotA,
                     lists:flatten(io_lib:format("AK mismatch in ~s",  [Name])))
    end, sets()),
    %% EPS profile (Set1): CK=128, IK=128, RES=64 — use behaviour callbacks
    {_Name1, K1, RAND1, _SQN1, _AMF1, TOP1, Iters1, _TOPc1, _, _, _, _, _, _, _} = hd(sets()),
    BinK1  = ?H(K1),
    TOPc1  = udr_crypto_tuak:topc_gen(BinK1, ?H(TOP1), Iters1),
    GotCK  = udr_crypto_tuak:f3(BinK1, TOPc1, ?H(RAND1)),
    GotIK  = udr_crypto_tuak:f4(BinK1, TOPc1, ?H(RAND1)),
    GotAK  = udr_crypto_tuak:f5(BinK1, TOPc1, ?H(RAND1)),
    ?assertEqual(16, byte_size(GotCK)),
    ?assertEqual(16, byte_size(GotIK)),
    ?assertEqual(6,  byte_size(GotAK)).

f5star(_Config) ->
    lists:foreach(fun({Name, K, RAND, _SQN, _AMF, TOP, Iters, _TOPc, _, _, _, _, _, _, F5S}) ->
        BinK = ?H(K),
        TOPc = udr_crypto_tuak:topc_gen(BinK, ?H(TOP), Iters),
        Got  = udr_crypto_tuak:f5star_core(BinK, TOPc, ?H(RAND), Iters),
        ?assertEqual(?H(F5S), Got,
                     lists:flatten(io_lib:format("F5* mismatch in ~s", [Name])))
    end, sets()),
    %% EPS f5star callback (Set1)
    {_Name1, K1, RAND1, _SQN1, _AMF1, TOP1, Iters1, _TOPc1, _, _, _, _, _, _, _} = hd(sets()),
    BinK1 = ?H(K1),
    TOPc1 = udr_crypto_tuak:topc_gen(BinK1, ?H(TOP1), Iters1),
    GotF5S = udr_crypto_tuak:f5star(BinK1, TOPc1, ?H(RAND1)),
    ?assertEqual(6, byte_size(GotF5S)).
