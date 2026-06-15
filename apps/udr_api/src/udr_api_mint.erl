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
           "Contrast `udr_api_subscriber`, which takes caller-supplied Ki/OP.\n\n"
           "SQN starts at 0 (a fresh subscriber). Re-minting an IMSI requires an\n"
           "explicit delete of its auth_subscription first; that resets SQN to 0 and,\n"
           "if the physical USIM retained a higher SQN_MS, forces an AUTS resync on the\n"
           "next attach. Re-mint deliberately, not as a routine operation.".

-export([provision/1]).

-type req() :: #{imsi := binary(), msisdn := binary(), iccid := binary(),
                 amf => binary(), profile => map()}.

-type error_reason() :: invalid_request | invalid_identity
                      | op_not_configured | op_misconfigured
                      | invalid_amf | amf_not_configured | amf_misconfigured
                      | already_provisioned | session_busy
                      | {storage, term()}.

-doc "Mint credentials for a subscriber and store the HSS records. Generates Ki,\n"
     "derives OPc from the configured operator OP, writes subscription_data then\n"
     "auth_subscription, and returns the IMSI/ICCID handle. Runs under the\n"
     "cluster-wide per-IMSI lock. Errors: `invalid_request` (missing identity keys),\n"
     "`invalid_identity` (malformed IMSI/MSISDN/ICCID), `op_*`/`amf_*` (misconfig),\n"
     "`invalid_amf` (bad per-call amf), `already_provisioned`, `session_busy` (lock\n"
     "contended), `{storage, Reason}` (backend write failed).".
-spec provision(req()) ->
    {ok, #{imsi := binary(), iccid := binary()}} | {error, error_reason()}.
provision(#{imsi := Imsi, msisdn := Msisdn, iccid := Iccid} = Req) ->
    case validate_identity(Imsi, Msisdn, Iccid) of
        {error, _} = E ->
            E;
        ok ->
            case {op(), amf(Req)} of
                {{error, _} = E, _} -> E;
                {_, {error, _} = E} -> E;
                {{ok, OP}, {ok, Amf}} ->
                    udr_cluster:with_session(
                      Imsi, fun() -> do_provision(Imsi, Msisdn, Iccid, OP, Amf, Req) end)
            end
    end;
provision(_) ->
    {error, invalid_request}.

-spec do_provision(binary(), binary(), binary(), binary(), binary(), req()) ->
    {ok, #{imsi := binary(), iccid := binary()}}
    | {error, already_provisioned | {storage, term()}}.
do_provision(Imsi, Msisdn, Iccid, OP, Amf, Req) ->
    case udr_data:get_authentication_subscription(Imsi) of
        {ok, _Existing} ->
            {error, already_provisioned};
        {error, not_found} ->
            Ki   = crypto:strong_rand_bytes(16),
            OPc  = udr_crypto:opc(milenage, Ki, OP),
            Auth = udr_api_subscriber:auth_record(Ki, OPc, <<"milenage">>, Amf, 0),
            Profile = profile(Imsi, Msisdn, Iccid, Req),
            %% auth_subscription is the commit marker the guard above keys on, so
            %% write the profile first and the credentials last. A mint interrupted
            %% by a storage error or a crash then leaves auth_subscription absent,
            %% so a retry safely re-runs and completes -- never a stuck half-state.
            case udr_data:put_subscription_data(Imsi, Profile) of
                {error, Reason} ->
                    {error, {storage, Reason}};
                ok ->
                    case udr_data:put_authentication_subscription(Imsi, Auth) of
                        ok              -> {ok, #{imsi => Imsi, iccid => Iccid}};
                        {error, Reason} -> {error, {storage, Reason}}
                    end
            end
    end.

%% Build subscription_data non-destructively: identity fields (msisdn/iccid)
%% override the caller profile, which overrides any pre-existing stored profile.
%% Merging the existing record means a re-mint (auth absent, profile present)
%% preserves the operator's profile fields instead of clobbering them.
-spec profile(binary(), binary(), binary(), req()) -> map().
profile(Imsi, Msisdn, Iccid, Req) ->
    Existing = case udr_data:get_subscription_data(Imsi) of
                   {ok, P}            -> P;
                   {error, not_found} -> #{}
               end,
    Caller = maps:get(profile, Req, #{}),
    maps:merge(maps:merge(Existing, Caller),
               #{<<"msisdn">> => Msisdn, <<"iccid">> => Iccid}).

%% Read the operator-wide OP from config. Must be a 16-byte binary.
-spec op() -> {ok, binary()} | {error, op_not_configured | op_misconfigured}.
op() ->
    case application:get_env(udr_api, op) of
        {ok, OP} when is_binary(OP), byte_size(OP) =:= 16 -> {ok, OP};
        {ok, _}                                           -> {error, op_misconfigured};
        undefined                                         -> {error, op_not_configured}
    end.

%% AMF for this mint. A per-call `amf` (validated to 2 bytes) wins; otherwise the
%% operator-wide `default_amf` must be configured. There is no built-in default:
%% AMF participates in the AUTN MAC, so a wrong/placeholder value fails every
%% authentication in the field -- fail closed (like op/0) rather than guess.
-spec amf(req()) -> {ok, binary()} | {error, invalid_amf | amf_not_configured | amf_misconfigured}.
amf(Req) ->
    case maps:find(amf, Req) of
        {ok, Amf} when is_binary(Amf), byte_size(Amf) =:= 2 -> {ok, Amf};
        {ok, _}                                             -> {error, invalid_amf};
        error                                               -> default_amf()
    end.

-spec default_amf() -> {ok, binary()} | {error, amf_not_configured | amf_misconfigured}.
default_amf() ->
    case application:get_env(udr_api, default_amf) of
        {ok, Amf} when is_binary(Amf), byte_size(Amf) =:= 2 -> {ok, Amf};
        {ok, _}                                             -> {error, amf_misconfigured};
        undefined                                           -> {error, amf_not_configured}
    end.

%% IMSI/MSISDN/ICCID are numeric identifiers used as lock and storage keys.
%% Reject empty/garbage so a malformed identity can never become a key.
-spec validate_identity(term(), term(), term()) -> ok | {error, invalid_identity}.
validate_identity(Imsi, Msisdn, Iccid) ->
    case is_digits(Imsi, 6, 15) andalso is_digits(Msisdn, 1, 15)
         andalso is_digits(Iccid, 18, 22) of
        true  -> ok;
        false -> {error, invalid_identity}
    end.

-spec is_digits(term(), pos_integer(), pos_integer()) -> boolean().
is_digits(B, Lo, Hi) when is_binary(B), byte_size(B) >= Lo, byte_size(B) =< Hi ->
    lists:all(fun(C) -> C >= $0 andalso C =< $9 end, binary_to_list(B));
is_digits(_, _, _) ->
    false.
