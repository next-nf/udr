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
-module(udr_crypto_algo).
-moduledoc "Behaviour for authentication algorithm sets (MILENAGE now, TUAK later).".

-callback opc(K :: binary(), OP :: binary()) -> binary().
-callback f1(binary(), binary(), binary(), binary(), binary()) -> binary().
-callback f1star(binary(), binary(), binary(), binary(), binary()) -> binary().
-callback f2(binary(), binary(), binary()) -> binary().
-callback f3(binary(), binary(), binary()) -> binary().
-callback f4(binary(), binary(), binary()) -> binary().
-callback f5(binary(), binary(), binary()) -> binary().
-callback f5star(binary(), binary(), binary()) -> binary().
