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
-module(udr_crypto_prop_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([resync_roundtrip/1, resync_roundtrip_tuak/1]).

b(N) -> proper_types:binary(N).

all() -> [resync_roundtrip, resync_roundtrip_tuak].

prop_resync_roundtrip() ->
    ?FORALL({K, OPc, RAND, SqnMs},
            {b(16), b(16), b(16), b(6)},
            begin
                AkStar = udr_crypto_milenage:f5star(K, OPc, RAND),
                Conc   = crypto:exor(SqnMs, AkStar),
                MacS   = udr_crypto_milenage:f1star(K, OPc, RAND, SqnMs, <<0:16>>),
                AUTS   = <<Conc/binary, MacS/binary>>,
                {ok, SqnMs} =:= udr_crypto:verify_resync(milenage, K, OPc, RAND, AUTS)
            end).

resync_roundtrip(_Config) ->
    ?assert(proper:quickcheck(prop_resync_roundtrip(), [{numtests, 200}, quiet])),
    ok.

%% TUAK: K is 16 or 32 bytes, TOPc is 32 bytes. Build AUTS with f5*/f1* and verify.
prop_resync_roundtrip_tuak() ->
    ?FORALL({K, TOPc, RAND, SqnMs},
            {proper_types:oneof([b(16), b(32)]), b(32), b(16), b(6)},
            begin
                AkStar = udr_crypto_tuak:f5star(K, TOPc, RAND),
                Conc   = crypto:exor(SqnMs, AkStar),
                MacS   = udr_crypto_tuak:f1star(K, TOPc, RAND, SqnMs, <<0:16>>),
                AUTS   = <<Conc/binary, MacS/binary>>,
                {ok, SqnMs} =:= udr_crypto:verify_resync(tuak, K, TOPc, RAND, AUTS)
            end).

resync_roundtrip_tuak(_Config) ->
    ?assert(proper:quickcheck(prop_resync_roundtrip_tuak(), [{numtests, 200}, quiet])),
    ok.
