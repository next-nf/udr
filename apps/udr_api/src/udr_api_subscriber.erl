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
-module(udr_api_subscriber).
-moduledoc "Pure conversion between the provisioning JSON shape (hex strings) and the\n"
           "udr_data storage maps (binaries). OP->OPc is derived here at provisioning.".
-export([auth_from_json/1, profile_from_json/1, to_view/2]).

-doc "Convert the JSON `auth` object to the udr_data auth_subscription map.\n"
     "Hex fields -> binaries; derives OPc from OP if `opc` is absent; throws `badarg`\n"
     "if neither opc nor op is present (caller maps to 400).".
-spec auth_from_json(map()) -> map().
auth_from_json(#{<<"ki">> := KiHex, <<"amf">> := AmfHex} = J) ->
    Ki   = hex(KiHex),
    Algo = maps:get(<<"algorithm">>, J, <<"milenage">>),
    Amf  = hex(AmfHex),
    Sqn  = maps:get(<<"sqn">>, J, 0),
    OPc  = opc(J, Algo, Ki),
    #{<<"ki">> => Ki, <<"opc">> => OPc, <<"algorithm">> => Algo,
      <<"amf">> => Amf, <<"sqn">> => Sqn}.

-doc "The profile JSON is already document-shaped; passed through to storage as-is.".
-spec profile_from_json(map()) -> map().
profile_from_json(P) -> P.

-doc "Build a GET response view: auth metadata only (NO ki/opc secrets) + profile.".
-spec to_view(map(), map()) -> map().
to_view(Auth, Profile) ->
    AuthView = #{<<"algorithm">> => maps:get(<<"algorithm">>, Auth, <<"milenage">>),
                 <<"amf">> => binary:encode_hex(maps:get(<<"amf">>, Auth, <<>>)),
                 <<"sqn">> => maps:get(<<"sqn">>, Auth, 0)},
    #{<<"auth">> => AuthView, <<"profile">> => Profile}.

%% OPc: prefer explicit opc; else derive from op via udr_crypto; else badarg.
-spec opc(map(), binary(), binary()) -> binary().
opc(J, Algo, Ki) ->
    case maps:find(<<"opc">>, J) of
        {ok, OpcHex} -> hex(OpcHex);
        error ->
            case maps:find(<<"op">>, J) of
                {ok, OpHex} -> udr_crypto:opc(algo(Algo), Ki, hex(OpHex));
                error       -> erlang:error(badarg)
            end
    end.

-spec algo(binary()) -> udr_crypto:algo().
%% Unknown algorithm -> function_clause (caught by the handler -> 400).
algo(<<"milenage">>) -> milenage.

-spec hex(binary()) -> binary().
hex(H) -> binary:decode_hex(H).
