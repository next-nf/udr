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

-module(udr_crypto_kdf).
-moduledoc "3GPP key derivation: generic KDF (TS 33.220) and EPS KASME (TS 33.401 A.2).".

-export([kdf/2, kasme/4]).

-doc "Generic 3GPP KDF: HMAC-SHA-256 of S under Key. Returns 32 bytes.".
-spec kdf(Key :: binary(), S :: binary()) -> binary().
kdf(Key, S) ->
    crypto:mac(hmac, sha256, Key, S).

-doc "Derive KASME (32 bytes). SnId is the 3-byte serving-network id (Visited-PLMN-Id);\n"
     "SqnXorAk is the 6-byte (SQN XOR AK). S = 0x10 ‖ SnId ‖ 0x0003 ‖ SqnXorAk ‖ 0x0006.".
-spec kasme(CK :: binary(), IK :: binary(), SnId :: binary(), SqnXorAk :: binary()) -> binary().
kasme(CK, IK, SnId, SqnXorAk)
  when byte_size(CK) =:= 16, byte_size(IK) =:= 16,
       byte_size(SnId) =:= 3, byte_size(SqnXorAk) =:= 6 ->
    S = <<16#10, SnId/binary, 16#00, 16#03, SqnXorAk/binary, 16#00, 16#06>>,
    kdf(<<CK/binary, IK/binary>>, S).
