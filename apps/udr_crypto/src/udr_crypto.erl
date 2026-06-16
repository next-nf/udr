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
-module(udr_crypto).
-moduledoc "Public API for HSS authentication crypto (MILENAGE / EPS-AKA).".

%% OTP-29 native record: definition is captured into each value, so it survives
%% module reloads across a rolling cluster upgrade. Never define in a .hrl.
-record #eps_av{
    rand  = <<>> :: binary(),   %% 16 bytes
    xres  = <<>> :: binary(),   %% 8 bytes
    autn  = <<>> :: binary(),   %% 16 bytes
    kasme = <<>> :: binary()    %% 32 bytes
}.
-export_record([eps_av]).

-export([eps_vector/7, generate_eps_vectors/7, verify_resync/5, opc/3]).
-export_type([algo/0]).

-type algo() :: milenage | tuak.
-type eps_av() :: term().  %% native-record value; term() keeps dialyzer happy (experimental feature)

-doc "Compute one EPS-AKA authentication vector for a supplied RAND (pure).\n"
     "Returns an `eps_av` native record {RAND, XRES, AUTN, KASME}.".
-spec eps_vector(Algo :: algo(), K :: binary(), OPc :: binary(), AMF :: binary(),
                 SQN :: binary(), RAND :: binary(), SnId :: binary()) -> eps_av().
eps_vector(Algo, K, OPc, AMF, SQN, RAND, SnId) ->
    M = algo_module(Algo),
    MacA = M:f1(K, OPc, RAND, SQN, AMF),
    Res  = M:f2(K, OPc, RAND),
    CK   = M:f3(K, OPc, RAND),
    IK   = M:f4(K, OPc, RAND),
    AK   = M:f5(K, OPc, RAND),
    SqnXorAk = crypto:exor(SQN, AK),
    AUTN  = <<SqnXorAk/binary, AMF/binary, MacA/binary>>,
    Kasme = udr_crypto_kdf:kasme(CK, IK, SnId, SqnXorAk),
    #eps_av{rand = RAND, xres = Res, autn = AUTN, kasme = Kasme}.

-doc "Generate N EPS vectors with fresh random RANDs, advancing SQN by 1 per vector.\n"
     "SQN is a 48-bit integer; returns {Vectors, NextSqn} so the caller persists NextSqn.".
-spec generate_eps_vectors(Algo :: algo(), K :: binary(), OPc :: binary(), AMF :: binary(),
                           Sqn0 :: non_neg_integer(), N :: pos_integer(), SnId :: binary())
                          -> {[eps_av()], non_neg_integer()}.
generate_eps_vectors(Algo, K, OPc, AMF, Sqn0, N, SnId) ->
    lists:foldl(
      fun(_, {Acc, Sqn}) ->
          RAND = crypto:strong_rand_bytes(16),
          V = eps_vector(Algo, K, OPc, AMF, <<Sqn:48>>, RAND, SnId),
          {[V | Acc], Sqn + 1}
      end,
      {[], Sqn0},
      lists:seq(1, N)).

-doc "Derive OPc from K and OP using the selected algorithm's OPc derivation.".
-spec opc(Algo :: algo(), K :: binary(), OP :: binary()) -> binary().
opc(Algo, K, OP) ->
    M = algo_module(Algo),
    M:opc(K, OP).

-doc "Verify an AUTS resync token. AUTS = (SQN_MS XOR AK*) ‖ MAC-S (14 bytes).\n"
     "The resync MAC uses the dummy AMF 0x0000 (TS 33.102). Returns {ok, SqnMs}\n"
     "(SqnMs is a 6-byte binary) or {error, mac_failure}.".
-spec verify_resync(Algo :: algo(), K :: binary(), OPc :: binary(),
                    RAND :: binary(), AUTS :: binary())
                   -> {ok, binary()} | {error, mac_failure}.
verify_resync(Algo, K, OPc, RAND, <<Conc:6/binary, MacS:8/binary>>) ->
    M = algo_module(Algo),
    AkStar = M:f5star(K, OPc, RAND),
    SqnMs  = crypto:exor(Conc, AkStar),
    XMacS  = M:f1star(K, OPc, RAND, SqnMs, <<0:16>>),
    case crypto:hash_equals(MacS, XMacS) of
        true  -> {ok, SqnMs};
        false -> {error, mac_failure}
    end.

algo_module(milenage) -> udr_crypto_milenage;
algo_module(tuak)     -> udr_crypto_tuak.
