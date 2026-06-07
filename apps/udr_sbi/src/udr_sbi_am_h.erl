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
-module(udr_sbi_am_h).
-moduledoc "Nudr-DR provisioned-data/am-data resource (GET; Access-and-Mobility data).".
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
    case udr_data:get_am_subscription(Imsi) of
        {ok, Am}           -> udr_sbi:reply_json(Req, 200, Am, []);
        {error, not_found} -> udr_sbi:problem(Req, 404, <<"Not Found">>,
                                              <<"am-data not found">>)
    end;
handle(_M, _Imsi, Req) ->
    udr_sbi:problem(Req, 405, <<"Method Not Allowed">>, <<"only GET is supported">>).
