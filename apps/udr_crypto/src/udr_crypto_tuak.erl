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

-module(udr_crypto_tuak).
-moduledoc "TUAK algorithm set (3GPP TS 35.231): f1-f5, f1*, f5*, TOPc, over Keccak-f[1600].".
-behaviour(udr_crypto_algo).

-export([opc/2, f1/5, f1star/5, f2/3, f3/3, f4/3, f5/3, f5star/3]).
-export([topc_gen/3, f1_core/7, f1star_core/7, f2345_core/5, f5star_core/4]).

-define(ALGONAME, <<"TUAK1.0">>).

-spec topc_gen(binary(), binary(), pos_integer()) -> binary().
topc_gen(K, TOP, Iters)
  when byte_size(TOP) =:= 32, (byte_size(K) =:= 16 orelse byte_size(K) =:= 32) ->
    Out = udr_crypto_keccak:permute(build(k256(K), TOP, <<0:128>>, <<0:64>>, K), Iters),
    revb(binary:part(Out, 0, 32)).

-spec opc(binary(), binary()) -> binary().
opc(K, TOP) -> topc_gen(K, TOP, 1).

-spec f1_core(binary(),binary(),binary(),binary(),binary(),pos_integer(),pos_integer()) -> binary().
f1_core(K, TOPc, RAND, SQN, AMF, MacLen, Iters)
  when byte_size(TOPc) =:= 32, byte_size(RAND) =:= 16, byte_size(SQN) =:= 6, byte_size(AMF) =:= 2 ->
    Out = udr_crypto_keccak:permute(build(mac_instance(16#00, MacLen, K), TOPc, RAND,
              <<(revb(AMF))/binary, (revb(SQN))/binary>>, K), Iters),
    revb(binary:part(Out, 0, MacLen)).

-spec f1star_core(binary(),binary(),binary(),binary(),binary(),pos_integer(),pos_integer()) -> binary().
f1star_core(K, TOPc, RAND, SQN, AMF, MacLen, Iters)
  when byte_size(TOPc) =:= 32, byte_size(RAND) =:= 16, byte_size(SQN) =:= 6, byte_size(AMF) =:= 2 ->
    Out = udr_crypto_keccak:permute(build(mac_instance(16#80, MacLen, K), TOPc, RAND,
              <<(revb(AMF))/binary, (revb(SQN))/binary>>, K), Iters),
    revb(binary:part(Out, 0, MacLen)).

-spec f2345_core(binary(),binary(),binary(),{pos_integer(),pos_integer(),pos_integer()},pos_integer())
      -> {binary(),binary(),binary(),binary()}.
f2345_core(K, TOPc, RAND, {ResLen,CkLen,IkLen}=Lens, Iters)
  when byte_size(TOPc) =:= 32, byte_size(RAND) =:= 16 ->
    Out = udr_crypto_keccak:permute(build(f2345_instance(Lens, K), TOPc, RAND, <<0:64>>, K), Iters),
    {revb(binary:part(Out, 0,  ResLen)),
     revb(binary:part(Out, 32, CkLen)),
     revb(binary:part(Out, 64, IkLen)),
     revb(binary:part(Out, 96, 6))}.

-spec f5star_core(binary(),binary(),binary(),pos_integer()) -> binary().
f5star_core(K, TOPc, RAND, Iters)
  when byte_size(TOPc) =:= 32, byte_size(RAND) =:= 16 ->
    Out = udr_crypto_keccak:permute(build(16#C0 + k256(K), TOPc, RAND, <<0:64>>, K), Iters),
    revb(binary:part(Out, 96, 6)).

-spec f1(binary(),binary(),binary(),binary(),binary()) -> binary().
f1(K, TOPc, RAND, SQN, AMF) -> f1_core(K, TOPc, RAND, SQN, AMF, 8, 1).
-spec f1star(binary(),binary(),binary(),binary(),binary()) -> binary().
f1star(K, TOPc, RAND, SQN, AMF) -> f1star_core(K, TOPc, RAND, SQN, AMF, 8, 1).
-spec f2(binary(),binary(),binary()) -> binary().
f2(K, TOPc, RAND) -> element(1, f2345_core(K, TOPc, RAND, {8,16,16}, 1)).
-spec f3(binary(),binary(),binary()) -> binary().
f3(K, TOPc, RAND) -> element(2, f2345_core(K, TOPc, RAND, {8,16,16}, 1)).
-spec f4(binary(),binary(),binary()) -> binary().
f4(K, TOPc, RAND) -> element(3, f2345_core(K, TOPc, RAND, {8,16,16}, 1)).
-spec f5(binary(),binary(),binary()) -> binary().
f5(K, TOPc, RAND) -> element(4, f2345_core(K, TOPc, RAND, {8,16,16}, 1)).
-spec f5star(binary(),binary(),binary()) -> binary().
f5star(K, TOPc, RAND) -> f5star_core(K, TOPc, RAND, 1).

build(Instance, Topc32, Rand16, AmfSqn8, K) ->
    KPad = case byte_size(K) of 16 -> <<(revb(K))/binary, 0:128>>; 32 -> revb(K) end,
    Filler = <<16#1F, 0:(38*8), 16#80, 0:(64*8)>>,
    Block = <<(revb(Topc32))/binary, Instance, (revb(?ALGONAME))/binary,
              (revb(Rand16))/binary, AmfSqn8/binary, KPad/binary, Filler/binary>>,
    200 = byte_size(Block),
    Block.

revb(B) -> list_to_binary(lists:reverse(binary_to_list(B))).
k256(K) -> case byte_size(K) of 32 -> 1; 16 -> 0 end.
mac_instance(Base, MacLen, K) -> Base + maclen_bits(MacLen) + k256(K).
maclen_bits(8) -> 16#08; maclen_bits(16) -> 16#10; maclen_bits(32) -> 16#20.
f2345_instance({ResLen, CkLen, IkLen}, K) ->
    16#40 + reslen_bits(ResLen)
          + (case CkLen of 32 -> 16#04; _ -> 0 end)
          + (case IkLen of 32 -> 16#02; _ -> 0 end)
          + k256(K).
reslen_bits(4) -> 16#00; reslen_bits(8) -> 16#08; reslen_bits(16) -> 16#10; reslen_bits(32) -> 16#20.
