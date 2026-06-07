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
-module(udr_sbi_registration_h).
-moduledoc "Nudr-DR context-data/amf-3gpp-access resource (serving-node registration).".
-export([init/2]).

init(Req0, State) ->
    UeId = cowboy_req:binding(ueId, Req0),
    Req = case udr_sbi:ue_imsi(UeId) of
              {ok, Imsi} -> handle(cowboy_req:method(Req0), Imsi, Req0);
              error      -> udr_sbi:problem(Req0, 400, <<"Bad Request">>,
                                            <<"invalid ueId (expected imsi-<digits>)">>)
          end,
    {ok, Req, State}.

handle(<<"GET">>, Imsi, Req) ->
    case udr_data:get_3gpp_access_registration(Imsi) of
        {ok, Reg}               -> udr_sbi:reply_json(Req, 200, Reg, []);
        {error, not_registered} -> udr_sbi:problem(Req, 404, <<"Not Found">>,
                                                   <<"no serving-node registration">>)
    end;
handle(<<"PUT">>, Imsi, Req0) ->
    {ok, Raw, Req1} = cowboy_req:read_body(Req0),
    try udr_sbi_json:decode(Raw) of
        Reg when is_map(Reg) ->
            case udr_data:put_3gpp_access_registration(Imsi, Reg) of
                ok         -> cowboy_req:reply(204, Req1);
                {error, _} -> udr_sbi:problem(Req1, 500, <<"Internal Server Error">>,
                                              <<"storage error">>)
            end;
        _ ->
            udr_sbi:problem(Req1, 400, <<"Bad Request">>, <<"body must be a JSON object">>)
    catch _:_ ->
        udr_sbi:problem(Req1, 400, <<"Bad Request">>, <<"invalid JSON body">>)
    end;
handle(<<"DELETE">>, Imsi, Req0) ->
    case udr_data:delete_3gpp_access_registration(Imsi) of
        ok         -> cowboy_req:reply(204, Req0);
        {error, _} -> udr_sbi:problem(Req0, 500, <<"Internal Server Error">>,
                                      <<"storage error">>)
    end;
handle(_M, _Imsi, Req) ->
    udr_sbi:problem(Req, 405, <<"Method Not Allowed">>, <<"GET, PUT, DELETE are supported">>).
