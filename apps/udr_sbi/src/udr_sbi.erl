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
-module(udr_sbi).
-moduledoc "Shared helpers for the Nudr SBI: ueId parsing, read-view shaping, and the\n"
           "JSON / problem+json reply helpers used by the resource handlers.".

-export([ue_imsi/1, strip_meta/1, auth_view/1, reply_json/4, problem/4]).

-doc "Parse a Nudr ueId of the form `imsi-<digits>` into the IMSI key; error otherwise.".
-spec ue_imsi(binary()) -> {ok, binary()} | error.
ue_imsi(<<"imsi-", Imsi/binary>>) when byte_size(Imsi) > 0 -> {ok, Imsi};
ue_imsi(_) -> error.

-doc "Drop the internal CAS metadata (version, _id) from a stored doc for a read view.".
-spec strip_meta(map()) -> map().
strip_meta(Doc) -> maps:without([<<"version">>, <<"_id">>], Doc).

-doc "Shape the stored auth subscription for the SBI: hex-encode ki/opc/amf, drop meta.".
-spec auth_view(map()) -> map().
auth_view(Auth) ->
    maps:map(fun(K, V) when K =:= <<"ki">>; K =:= <<"opc">>; K =:= <<"amf">> ->
                     binary:encode_hex(V, lowercase);
                (_K, V) -> V
             end, strip_meta(Auth)).

-doc "Reply with a JSON body.".
-spec reply_json(cowboy_req:req(), 100..599, map(), term()) -> cowboy_req:req().
reply_json(Req, Status, Map, _Opts) ->
    cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>},
                     udr_sbi_json:encode(Map), Req).

-doc "Reply with a 3GPP application/problem+json ProblemDetails body.".
-spec problem(cowboy_req:req(), 400..599, binary(), binary()) -> cowboy_req:req().
problem(Req, Status, Title, Detail) ->
    Body = udr_sbi_json:encode(#{<<"status">> => Status, <<"title">> => Title,
                                 <<"detail">> => Detail}),
    cowboy_req:reply(Status, #{<<"content-type">> => <<"application/problem+json">>}, Body, Req).
