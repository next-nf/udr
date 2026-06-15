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
-module(udr_api_http).
-moduledoc "Shared Cowboy reply helpers for the udr_api handlers (JSON bodies).".
-export([reply_json/3, reply_error/3]).

-doc "Reply with a JSON body. Sets content-type to application/json and encodes Map.".
-spec reply_json(cowboy:http_status(), map(), cowboy_req:req()) -> cowboy_req:req().
reply_json(Status, Map, Req) ->
    cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>},
                     udr_api_json:encode(Map), Req).

-doc "Reply with a JSON error envelope of the form {\"error\": Msg}.".
-spec reply_error(cowboy:http_status(), binary(), cowboy_req:req()) -> cowboy_req:req().
reply_error(Status, Msg, Req) ->
    reply_json(Status, #{<<"error">> => Msg}, Req).
