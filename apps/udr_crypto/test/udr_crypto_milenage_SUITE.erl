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

-module(udr_crypto_milenage_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([opc/1, f1/1, f2345/1]).

-define(H(S), binary:decode_hex(<<S>>)).

%% Set 1 inputs
-define(K1,   ?H("465b5ce8b199b49faa5f0a2ee238a6bc")).
-define(OPC1, ?H("cd63cb71954a9f4e48a5994e37a02baf")).
-define(RAND1,?H("23553cbe9637a89d218ae64dae47bf35")).
-define(SQN1, ?H("ff9bb4d0b607")).
-define(AMF1, ?H("b9b9")).

all() -> [opc, f1, f2345].

opc(_Config) ->
    ?assertEqual(?H("cd63cb71954a9f4e48a5994e37a02baf"),
                 udr_crypto_milenage:opc(?H("465b5ce8b199b49faa5f0a2ee238a6bc"),
                                         ?H("cdc202d5123e20f62b6d676ac72cb318"))),
    ?assertEqual(?H("53c15671c60a4b731c55b4a441c0bde2"),
                 udr_crypto_milenage:opc(?H("0396eb317b6d1c36f19c1c84cd6ffd16"),
                                         ?H("ff53bade17df5d4e793073ce9d7579fa"))),
    ?assertEqual(?H("1006020f0a478bf6b699f15c062e42b3"),
                 udr_crypto_milenage:opc(?H("fec86ba6eb707ed08905757b1bb44b8f"),
                                         ?H("dbc59adcb6f9a0ef735477b7fadf8374"))),
    ok.

f1(_Config) ->
    ?assertEqual(?H("4a9ffac354dfafb3"),
                 udr_crypto_milenage:f1(?K1, ?OPC1, ?RAND1, ?SQN1, ?AMF1)),
    ?assertEqual(?H("01cfaf9ec4e871e9"),
                 udr_crypto_milenage:f1star(?K1, ?OPC1, ?RAND1, ?SQN1, ?AMF1)),
    %% Set 3
    ?assertEqual(?H("9cabc3e99baf7281"),
                 udr_crypto_milenage:f1(?H("fec86ba6eb707ed08905757b1bb44b8f"),
                                        ?H("1006020f0a478bf6b699f15c062e42b3"),
                                        ?H("9f7c8d021accf4db213ccff0c7f71a6a"),
                                        ?H("9d0277595ffc"), ?H("725c"))),
    ?assertEqual(?H("95814ba2b3044324"),
                 udr_crypto_milenage:f1star(?H("fec86ba6eb707ed08905757b1bb44b8f"),
                                            ?H("1006020f0a478bf6b699f15c062e42b3"),
                                            ?H("9f7c8d021accf4db213ccff0c7f71a6a"),
                                            ?H("9d0277595ffc"), ?H("725c"))),
    ok.

f2345(_Config) ->
    ?assertEqual(?H("a54211d5e3ba50bf"), udr_crypto_milenage:f2(?K1, ?OPC1, ?RAND1)),
    ?assertEqual(?H("b40ba9a3c58b2a05bbf0d987b21bf8cb"),
                 udr_crypto_milenage:f3(?K1, ?OPC1, ?RAND1)),
    ?assertEqual(?H("f769bcd751044604127672711c6d3441"),
                 udr_crypto_milenage:f4(?K1, ?OPC1, ?RAND1)),
    ?assertEqual(?H("aa689c648370"), udr_crypto_milenage:f5(?K1, ?OPC1, ?RAND1)),
    ?assertEqual(?H("451e8beca43b"), udr_crypto_milenage:f5star(?K1, ?OPC1, ?RAND1)),
    %% Set 2 spot-checks
    ?assertEqual(?H("d3a628ed988620f0"),
                 udr_crypto_milenage:f2(?H("0396eb317b6d1c36f19c1c84cd6ffd16"),
                                        ?H("53c15671c60a4b731c55b4a441c0bde2"),
                                        ?H("c00d603103dcee52c4478119494202e8"))),
    ?assertEqual(?H("c47783995f72"),
                 udr_crypto_milenage:f5(?H("0396eb317b6d1c36f19c1c84cd6ffd16"),
                                        ?H("53c15671c60a4b731c55b4a441c0bde2"),
                                        ?H("c00d603103dcee52c4478119494202e8"))),
    ?assertEqual(?H("30f1197061c1"),
                 udr_crypto_milenage:f5star(?H("0396eb317b6d1c36f19c1c84cd6ffd16"),
                                            ?H("53c15671c60a4b731c55b4a441c0bde2"),
                                            ?H("c00d603103dcee52c4478119494202e8"))),
    ok.
