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
-module(udr_api_mint_h).
-moduledoc "Cowboy handler for POST /provision/v1/subscribers/:imsi/mint.\n"
           "Server-side credential minting via udr_api_mint:provision/1 (non-idempotent;\n"
           "contrast the caller-supplied PUT on udr_api_subscriber_h).".
-export([init/2]).

-spec init(cowboy_req:req(), State) -> {ok, cowboy_req:req(), State}.
init(Req0, State) ->
    Imsi   = cowboy_req:binding(imsi, Req0),
    Method = cowboy_req:method(Req0),
    Req    = handle(Method, Imsi, Req0),
    {ok, Req, State}.

-spec handle(binary(), binary() | undefined, cowboy_req:req()) -> cowboy_req:req().
handle(<<"POST">>, Imsi, Req0) ->
    {ok, Raw, Req1} = cowboy_req:read_body(Req0),
    try
        Body    = udr_api_json:decode(Raw),
        MintReq = mint_req(Imsi, Body),
        respond(udr_api_mint:provision(MintReq), Req1)
    catch
        _:_ -> udr_api_http:reply_error(400, <<"invalid request body">>, Req1)
    end;
handle(_Method, _Imsi, Req0) ->
    udr_api_http:reply_json(405, #{<<"error">> => <<"method not allowed">>}, Req0).

%% Build the udr_api_mint request from the path imsi + JSON body. amf is hex.
-spec mint_req(binary(), map()) -> map().
mint_req(Imsi, Body) ->
    Base = #{imsi   => Imsi,
             msisdn => maps:get(<<"msisdn">>, Body, undefined),
             iccid  => maps:get(<<"iccid">>, Body, undefined)},
    with_profile(with_amf(with_algorithm(Base, Body), Body), Body).

with_algorithm(Base, #{<<"algorithm">> := Algo}) when is_binary(Algo) -> Base#{algorithm => Algo};
with_algorithm(Base, _)                                               -> Base.

with_amf(Base, #{<<"amf">> := AmfHex}) -> Base#{amf => binary:decode_hex(AmfHex)};
with_amf(Base, _)                      -> Base.

with_profile(Base, #{<<"profile">> := P}) when is_map(P) -> Base#{profile => P};
with_profile(Base, _)                                    -> Base.

-spec respond({ok, map()} | {error, term()}, cowboy_req:req()) -> cowboy_req:req().
respond({ok, #{imsi := I, iccid := C}}, Req) ->
    udr_api_http:reply_json(201, #{<<"imsi">> => I, <<"iccid">> => C,
                                   <<"status">> => <<"minted">>}, Req);
respond({error, session_busy}, Req0) ->
    Req = cowboy_req:set_resp_header(<<"retry-after">>, <<"1">>, Req0),
    udr_api_http:reply_error(503, <<"lock contended, retry">>, Req);
respond({error, Reason}, Req) ->
    {Status, Msg} = error_info(Reason),
    udr_api_http:reply_error(Status, Msg, Req).

-spec error_info(term()) -> {cowboy:http_status(), binary()}.
error_info(invalid_request)     -> {400, <<"missing required fields (msisdn, iccid)">>};
error_info(invalid_identity)    -> {400, <<"invalid imsi/msisdn/iccid">>};
error_info(invalid_amf)         -> {400, <<"amf must be 2 bytes (hex)">>};
error_info(unsupported_algorithm) -> {400, <<"unsupported algorithm (expected milenage or tuak)">>};
error_info(already_provisioned) -> {409, <<"subscriber already provisioned">>};
error_info(op_not_configured)   -> {500, <<"operator OP not configured">>};
error_info(op_misconfigured)    -> {500, <<"operator OP misconfigured">>};
error_info(top_not_configured)  -> {500, <<"operator TOP (tuak) not configured">>};
error_info(top_misconfigured)   -> {500, <<"operator TOP (tuak) misconfigured">>};
error_info(amf_not_configured)  -> {500, <<"default AMF not configured">>};
error_info(amf_misconfigured)   -> {500, <<"default AMF misconfigured">>};
error_info({storage, _})        -> {500, <<"storage error">>}.
