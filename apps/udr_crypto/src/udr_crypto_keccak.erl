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

-module(udr_crypto_keccak).
-moduledoc "Keccak-f[1600] permutation (FIPS 202 / TS 35.231 primitive).".

-export([permute/1, permute/2]).

-define(MASK64, 16#FFFFFFFFFFFFFFFF).
-define(NROUNDS, 24).

-define(RC, {16#0000000000000001,16#0000000000008082,16#800000000000808A,16#8000000080008000,
             16#000000000000808B,16#0000000080000001,16#8000000080008081,16#8000000000008009,
             16#000000000000008A,16#0000000000000088,16#0000000080008009,16#000000008000000A,
             16#000000008000808B,16#800000000000008B,16#8000000000008089,16#8000000000008003,
             16#8000000000008002,16#8000000000000080,16#000000000000800A,16#800000008000000A,
             16#8000000080008081,16#8000000000008080,16#0000000080000001,16#8000000080008008}).

%% Rho rotation offsets in lane-index (x+5y) order.
-define(RHO, {0,1,62,28,27, 36,44,6,55,20, 3,10,43,25,39, 41,45,15,21,8, 18,2,61,56,14}).

-doc "Apply Keccak-f[1600] once to a 200-byte (1600-bit) state. Returns 200 bytes.".
-spec permute(binary()) -> binary().
permute(Bin) when byte_size(Bin) =:= 200 ->
    Lanes = [ L || <<L:64/little>> <= Bin ],
    Out = rounds(list_to_tuple(Lanes), 0),
    << <<L:64/little>> || L <- tuple_to_list(Out) >>.

-doc "Apply Keccak-f[1600] N times in succession (TUAK's iteration parameter).".
-spec permute(binary(), pos_integer()) -> binary().
permute(Bin, 1) -> permute(Bin);
permute(Bin, N) when is_integer(N), N > 1 -> permute(permute(Bin), N - 1).

rounds(A, ?NROUNDS) -> A;
rounds(A, R) -> rounds(iota(chi(rho_pi(theta(A))), R), R + 1).

theta(A) ->
    C = [ lane(A,X,0) bxor lane(A,X,1) bxor lane(A,X,2) bxor lane(A,X,3) bxor lane(A,X,4)
          || X <- [0,1,2,3,4] ],
    CT = list_to_tuple(C),
    D = [ el(CT,(X+4) rem 5) bxor rotl(el(CT,(X+1) rem 5), 1) || X <- [0,1,2,3,4] ],
    DT = list_to_tuple(D),
    map_xy(A, fun(V,X,_Y) -> V bxor el(DT,X) end).

rho_pi(A) ->
    lists:foldl(
      fun(I, Acc) ->
          X = I rem 5, Y = I div 5,
          NX = Y, NY = (2*X + 3*Y) rem 5,
          set(Acc, NX, NY, rotl(el(A,I), el(?RHO, I)))
      end, A, lists:seq(0,24)).

chi(B) ->
    map_xy(B, fun(_V,X,Y) ->
        lane(B,X,Y) bxor (((bnot lane(B,(X+1) rem 5,Y)) band ?MASK64) band lane(B,(X+2) rem 5,Y))
    end).

iota(A, R) -> set(A, 0, 0, lane(A,0,0) bxor element(R+1, ?RC)).

lane(A, X, Y) -> el(A, X + 5*Y).
el(T, I)      -> element(I+1, T).
set(T, X, Y, V) -> setelement(X + 5*Y + 1, T, V).
map_xy(A, F)  ->
    list_to_tuple([ F(el(A,I), I rem 5, I div 5) || I <- lists:seq(0,24) ]).
rotl(_V, 0) -> _V;
rotl(V, N) -> ((V bsl N) bor (V bsr (64-N))) band ?MASK64.
