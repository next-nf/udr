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
-module(udr_api_json).
-moduledoc "Thin native-`json` wrapper (binary-keyed maps).".
-export([decode/1, encode/1]).

-doc "Decode a JSON binary into an Erlang term (objects -> binary-keyed maps).".
-spec decode(binary()) -> term().
decode(Bin) ->
    json:decode(Bin).

-doc "Encode an Erlang term to a JSON binary.".
-spec encode(term()) -> binary().
encode(Term) ->
    iolist_to_binary(json:encode(Term)).
