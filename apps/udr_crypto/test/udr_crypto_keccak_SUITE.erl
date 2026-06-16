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

-module(udr_crypto_keccak_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, sha3_256_oracle/1, state_roundtrip/1, permute_iterations/1]).

all() -> [sha3_256_oracle, state_roundtrip, permute_iterations].

%% SHA3-256: rate=136 bytes, capacity=64 bytes, domain byte 0x06, pad10*1.
sha3_256(Msg) ->
    Rate = 136,
    Padded = pad(Msg, Rate),
    State0 = <<0:1600>>,
    Absorbed = absorb(State0, Padded, Rate),
    <<Out:32/binary, _/binary>> = Absorbed,
    Out.

pad(Msg, Rate) ->
    PadLen = Rate - (byte_size(Msg) rem Rate),
    Pad = case PadLen of
              1 -> <<16#86>>;
              N -> <<16#06, 0:((N-2)*8), 16#80>>
          end,
    <<Msg/binary, Pad/binary>>.

absorb(State, <<>>, _Rate) -> State;
absorb(State, Bin, Rate) ->
    <<Block:Rate/binary, Rest/binary>> = Bin,
    Pad = (200 - Rate) * 8,
    XorBlock = crypto:exor(State, <<Block/binary, 0:Pad>>),
    absorb(udr_crypto_keccak:permute(XorBlock), Rest, Rate).

sha3_256_oracle(_Config) ->
    Cases = [<<>>, <<"abc">>, <<"The quick brown fox jumps over the lazy dog">>,
             binary:copy(<<"x">>, 135), binary:copy(<<"y">>, 136),
             binary:copy(<<"z">>, 137), crypto:strong_rand_bytes(500)],
    [ ?assertEqual(crypto:hash(sha3_256, M), sha3_256(M)) || M <- Cases ],
    ok.

state_roundtrip(_Config) ->
    In = crypto:strong_rand_bytes(200),
    Out = udr_crypto_keccak:permute(In),
    ?assertEqual(200, byte_size(Out)),
    ?assertEqual(Out, udr_crypto_keccak:permute(In)),
    ?assertNotEqual(In, Out),
    ok.

%% permute/2 applies the permutation N times; check it against manual composition.
permute_iterations(_Config) ->
    In = crypto:strong_rand_bytes(200),
    ?assertEqual(udr_crypto_keccak:permute(In), udr_crypto_keccak:permute(In, 1)),
    ?assertEqual(udr_crypto_keccak:permute(udr_crypto_keccak:permute(In)),
                 udr_crypto_keccak:permute(In, 2)),
    ?assertEqual(udr_crypto_keccak:permute(udr_crypto_keccak:permute(
                     udr_crypto_keccak:permute(In))),
                 udr_crypto_keccak:permute(In, 3)),
    ok.
