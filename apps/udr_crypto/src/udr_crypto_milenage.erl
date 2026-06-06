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

-module(udr_crypto_milenage).
-moduledoc "MILENAGE algorithm set (3GPP TS 35.205/206): f1–f5, f1*, f5*, OPc.".
-behaviour(udr_crypto_algo).

-export([opc/2, f1/5, f1star/5, f2/3, f3/3, f4/3, f5/3, f5star/3]).

-doc "Derive OPc from the subscriber key K and operator constant OP.\n"
     "OPc = OP XOR E_K(OP). K, OP, OPc are 16-byte binaries.".
-spec opc(K :: binary(), OP :: binary()) -> binary().
opc(K, OP) when byte_size(K) =:= 16, byte_size(OP) =:= 16 ->
    crypto:exor(OP, block(K, OP)).

%% MILENAGE constants (TS 35.206 §4.1): rotations in bits, c-constants as 128-bit ints.
-define(C1, <<0:128>>).  -define(R1, 64).
-define(C2, <<1:128>>).  -define(R2, 0).
-define(C3, <<2:128>>).  -define(R3, 32).
-define(C4, <<4:128>>).  -define(R4, 64).
-define(C5, <<8:128>>).  -define(R5, 96).

-doc "f1: network authentication MAC-A (8 bytes).".
-spec f1(binary(), binary(), binary(), binary(), binary()) -> binary().
f1(K, OPc, RAND, SQN, AMF)
  when byte_size(K) =:= 16, byte_size(OPc) =:= 16, byte_size(RAND) =:= 16,
       byte_size(SQN) =:= 6, byte_size(AMF) =:= 2 ->
    <<MacA:8/binary, _MacS:8/binary>> = out1(K, OPc, RAND, SQN, AMF),
    MacA.

-doc "f1*: resync MAC-S (8 bytes). Same OUT1 computation; takes the lower 8 bytes.".
-spec f1star(binary(), binary(), binary(), binary(), binary()) -> binary().
f1star(K, OPc, RAND, SQN, AMF)
  when byte_size(K) =:= 16, byte_size(OPc) =:= 16, byte_size(RAND) =:= 16,
       byte_size(SQN) =:= 6, byte_size(AMF) =:= 2 ->
    <<_MacA:8/binary, MacS:8/binary>> = out1(K, OPc, RAND, SQN, AMF),
    MacS.

-doc "f2: response RES (8 bytes) — lower 8 bytes of OUT2.".
-spec f2(binary(), binary(), binary()) -> binary().
f2(K, OPc, RAND) ->
    <<_Ak:6/binary, _:2/binary, Res:8/binary>> = out(K, OPc, RAND, ?R2, ?C2),
    Res.

-doc "f3: confidentiality key CK (16 bytes).".
-spec f3(binary(), binary(), binary()) -> binary().
f3(K, OPc, RAND) -> out(K, OPc, RAND, ?R3, ?C3).

-doc "f4: integrity key IK (16 bytes).".
-spec f4(binary(), binary(), binary()) -> binary().
f4(K, OPc, RAND) -> out(K, OPc, RAND, ?R4, ?C4).

-doc "f5: anonymity key AK (6 bytes) — top 6 bytes of OUT2.".
-spec f5(binary(), binary(), binary()) -> binary().
f5(K, OPc, RAND) ->
    <<Ak:6/binary, _/binary>> = out(K, OPc, RAND, ?R2, ?C2),
    Ak.

-doc "f5*: resync anonymity key AK* (6 bytes) — top 6 bytes of OUT5.".
-spec f5star(binary(), binary(), binary()) -> binary().
f5star(K, OPc, RAND) ->
    <<Ak:6/binary, _/binary>> = out(K, OPc, RAND, ?R5, ?C5),
    Ak.

%% OUT_i = E_K( rot(TEMP XOR OPc, r_i) XOR c_i ) XOR OPc   (for i = 2..5)
-spec out(binary(), binary(), binary(), non_neg_integer(), binary()) -> binary().
out(K, OPc, RAND, R, C) ->
    Temp = temp(K, OPc, RAND),
    In   = crypto:exor(rotl(crypto:exor(Temp, OPc), R), C),
    crypto:exor(block(K, In), OPc).

-spec out1(binary(), binary(), binary(), binary(), binary()) -> binary().
out1(K, OPc, RAND, SQN, AMF) ->
    Temp = temp(K, OPc, RAND),
    IN1  = <<SQN/binary, AMF/binary, SQN/binary, AMF/binary>>,
    In   = exor3(Temp, rotl(crypto:exor(IN1, OPc), ?R1), ?C1),
    crypto:exor(block(K, In), OPc).

-spec temp(binary(), binary(), binary()) -> binary().
temp(K, OPc, RAND) ->
    block(K, crypto:exor(RAND, OPc)).

-spec exor3(binary(), binary(), binary()) -> binary().
exor3(A, B, C) ->
    crypto:exor(crypto:exor(A, B), C).

%% Cyclic left rotation of a 128-bit binary by R bits.
-spec rotl(binary(), non_neg_integer()) -> binary().
rotl(Bin, 0) -> Bin;
rotl(Bin, R) ->
    <<I:128>> = Bin,
    Mask = (1 bsl 128) - 1,
    Rot  = ((I bsl R) bor (I bsr (128 - R))) band Mask,
    <<Rot:128>>.

%% AES-128 ECB single-block encryption: E_K(X).
-spec block(binary(), binary()) -> binary().
block(K, X) ->
    crypto:crypto_one_time(aes_128_ecb, K, X, true).
