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

-module(udr_crypto_kdf_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([kasme/1]).

-define(H(S), binary:decode_hex(<<S>>)).

all() -> [kasme].

kasme(_Config) ->
    CK  = ?H("0544dbba021279e799d28e1bd87c1454"),
    IK  = ?H("e821de2175d4874e7ae971a89588bfd2"),
    SN  = ?H("00f110"),
    SAK = ?H("813d93cdad6d"),  %% SQN XOR AK
    ?assertEqual(?H("83ecc522e1a24e85a26f728ffe2e2147d2ed75fe25fa191ad66437e9cd922cf9"),
                 udr_crypto_kdf:kasme(CK, IK, SN, SAK)),
    ok.
