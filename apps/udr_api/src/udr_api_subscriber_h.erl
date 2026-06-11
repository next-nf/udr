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
-module(udr_api_subscriber_h).
-moduledoc "Cowboy handler for /provision/v1/subscribers/:imsi (PUT/GET/DELETE).".
-export([init/2]).

-spec init(cowboy_req:req(), State) -> {ok, cowboy_req:req(), State}.
init(Req0, State) ->
    Imsi   = cowboy_req:binding(imsi, Req0),
    Method = cowboy_req:method(Req0),
    Req    = handle(Method, Imsi, Req0),
    {ok, Req, State}.

-spec handle(binary(), binary() | undefined, cowboy_req:req()) -> cowboy_req:req().
handle(<<"PUT">>, Imsi, Req0) ->
    {ok, Raw, Req1} = cowboy_req:read_body(Req0),
    try
        case udr_api_json:decode(Raw) of
            #{<<"auth">> := AuthJson} = Body ->
                Auth    = udr_api_subscriber:auth_from_json(AuthJson),
                Profile = udr_api_subscriber:profile_from_json(maps:get(<<"profile">>, Body, #{})),
                case store(Imsi, Auth, Profile) of
                    ok ->
                        reply_json(201, #{<<"imsi">> => Imsi, <<"status">> => <<"provisioned">>}, Req1);
                    {error, _} ->
                        reply_error(500, <<"storage error">>, Req1)
                end;
            _ ->
                reply_error(400, <<"missing 'auth' object">>, Req1)
        end
    catch
        error:badarg -> reply_error(400, <<"auth requires 'opc' or 'op' (and 'ki','amf')">>, Req1);
        _:_          -> reply_error(400, <<"invalid request body">>, Req1)
    end;
handle(<<"GET">>, Imsi, Req0) ->
    case udr_data:get_authentication_subscription(Imsi) of
        {error, not_found} ->
            reply_error(404, <<"subscriber not found">>, Req0);
        {ok, Auth} ->
            Profile = case udr_data:get_subscription_data(Imsi) of
                          {ok, P} -> P;
                          {error, not_found} -> #{}
                      end,
            reply_json(200, udr_api_subscriber:to_view(Auth, Profile), Req0)
    end;
handle(<<"DELETE">>, Imsi, Req0) ->
    ok = udr_data:delete_authentication_subscription(Imsi),
    ok = udr_data:delete_subscription_data(Imsi),
    ok = udr_data:delete_3gpp_access_registration(Imsi),
    cowboy_req:reply(204, Req0);
handle(_Method, _Imsi, Req0) ->
    reply_json(404, #{<<"error">> => <<"not found">>}, Req0).

%% Persist auth then profile; first error short-circuits.
-spec store(binary(), map(), map()) -> ok | {error, term()}.
store(Imsi, Auth, Profile) ->
    case udr_data:put_authentication_subscription(Imsi, Auth) of
        ok             -> udr_data:put_subscription_data(Imsi, Profile);
        {error, _} = E -> E
    end.

-spec reply_json(cowboy:http_status(), map(), cowboy_req:req()) -> cowboy_req:req().
reply_json(Status, Map, Req) ->
    cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>},
                     udr_api_json:encode(Map), Req).

-spec reply_error(cowboy:http_status(), binary(), cowboy_req:req()) -> cowboy_req:req().
reply_error(Status, Msg, Req) ->
    reply_json(Status, #{<<"error">> => Msg}, Req).
