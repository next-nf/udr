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
-module(udr_db_mongo_bson).
-moduledoc "Recursive Erlang<->BSON value codec. comtihon encodes a raw binary() as a\n"
           "BSON string (corrupting non-UTF-8 secrets), so we wrap every binary value as\n"
           "`{bin, bin, V}` (true BSON binary, subtype 0) on write and unwrap on read.\n"
           "Map keys, integers, and other terms pass through unchanged.".
-export([encode_doc/1, decode_doc/1, encode_value/1, decode_value/1]).

-doc "Wrap all binary VALUES in a document map as BSON binary (recursively).".
-spec encode_doc(map()) -> map().
encode_doc(Doc) when is_map(Doc) ->
    maps:map(fun(_K, V) -> encode_value(V) end, Doc).

-doc "Wrap a single value: binary -> {bin,bin,_}; recurse maps/lists; else passthrough.".
-spec encode_value(term()) -> term().
encode_value(V) when is_binary(V) -> {bin, bin, V};
encode_value(V) when is_map(V)    -> maps:map(fun(_K, X) -> encode_value(X) end, V);
encode_value(V) when is_list(V)   -> [encode_value(X) || X <- V];
encode_value(V)                   -> V.

-doc "Unwrap BSON-binary values back to Erlang binaries (recursively).".
-spec decode_doc(map()) -> map().
decode_doc(Doc) when is_map(Doc) ->
    maps:map(fun(_K, V) -> decode_value(V) end, Doc).

-doc "Unwrap a single value: {bin,bin,_} -> binary; recurse maps/lists; else passthrough.".
-spec decode_value(term()) -> term().
decode_value({bin, bin, V})     -> V;
decode_value(V) when is_map(V)  -> maps:map(fun(_K, X) -> decode_value(X) end, V);
decode_value(V) when is_list(V) -> [decode_value(X) || X <- V];
decode_value(V)                 -> V.
