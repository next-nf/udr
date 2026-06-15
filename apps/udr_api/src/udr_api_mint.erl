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
-module(udr_api_mint).
-moduledoc "Server-side subscriber credential minting. Identity in (IMSI/MSISDN/\n"
           "ICCID), secrets minted: Ki is generated and OPc is derived from the sealed\n"
           "operator OP (`udr_api`/`op` config). Writes auth_subscription +\n"
           "subscription_data via `udr_data`. OP is read at mint time and never stored.\n"
           "Contrast `udr_api_subscriber`, which takes caller-supplied Ki/OP.".

-export([provision/1]).

-type req() :: #{imsi := binary(), msisdn := binary(), iccid := binary(),
                 amf => binary(), profile => map()}.

-define(DEFAULT_AMF, <<16#B9B9:16>>).

-doc "Mint credentials for a subscriber and store the HSS records. Generates Ki,\n"
     "derives OPc from the configured operator OP, writes auth_subscription and\n"
     "subscription_data, and returns the IMSI/ICCID handle. Runs under the\n"
     "cluster-wide per-IMSI lock; returns `{error, already_provisioned}` if the\n"
     "IMSI already has an auth_subscription, and `{error, session_busy}` if the\n"
     "lock cannot be acquired.".
-spec provision(req()) ->
    {ok, #{imsi := binary(), iccid := binary()}}
    | {error, already_provisioned | op_not_configured | op_misconfigured | session_busy}.
provision(#{imsi := Imsi, msisdn := Msisdn, iccid := Iccid} = Req) ->
    case op() of
        {error, _} = E ->
            E;
        {ok, OP} ->
            udr_cluster:with_session(
              Imsi, fun() -> do_provision(Imsi, Msisdn, Iccid, OP, Req) end)
    end.

%% Read the operator-wide OP from config. Must be a 16-byte binary.
-spec op() -> {ok, binary()} | {error, op_not_configured | op_misconfigured}.
op() ->
    case application:get_env(udr_api, op) of
        {ok, OP} when is_binary(OP), byte_size(OP) =:= 16 -> {ok, OP};
        {ok, _}                                           -> {error, op_misconfigured};
        undefined                                         -> {error, op_not_configured}
    end.

-spec do_provision(binary(), binary(), binary(), binary(), req()) ->
    {ok, #{imsi := binary(), iccid := binary()}} | {error, already_provisioned}.
do_provision(Imsi, Msisdn, Iccid, OP, Req) ->
    case udr_data:get_authentication_subscription(Imsi) of
        {ok, _Existing} ->
            {error, already_provisioned};
        {error, not_found} ->
            Ki  = crypto:strong_rand_bytes(16),
            OPc = udr_crypto:opc(milenage, Ki, OP),
            %% AMF precedence: per-call `amf` -> `default_amf` app env -> ?DEFAULT_AMF.
            Amf = maps:get(amf, Req,
                           application:get_env(udr_api, default_amf, ?DEFAULT_AMF)),
            Auth = #{<<"ki">>        => Ki,
                     <<"opc">>       => OPc,
                     <<"algorithm">> => <<"milenage">>,
                     <<"amf">>       => Amf,
                     <<"sqn">>       => 0},
            ok = udr_data:put_authentication_subscription(Imsi, Auth),
            %% Identity fields (msisdn/iccid) override any caller-supplied profile values.
            Base    = maps:get(profile, Req, #{}),
            Profile = maps:merge(Base, #{<<"msisdn">> => Msisdn, <<"iccid">> => Iccid}),
            ok = udr_data:put_subscription_data(Imsi, Profile),
            {ok, #{imsi => Imsi, iccid => Iccid}}
    end.
