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
-module(udr_data).
-moduledoc "Nudr-shaped HSS<->UDR data-access seam over `udr_db`. Resources are plain\n"
           "maps with binary keys; the internal `version` CAS token is hidden from callers.".

-export([put_authentication_subscription/2, get_authentication_subscription/1,
         advance_sqn/2, repair_sqn/2,
         put_subscription_data/2, get_subscription_data/1,
         get_am_subscription/1, get_sm_subscription/1,
         get_3gpp_access_registration/1, put_3gpp_access_registration/2,
         delete_3gpp_access_registration/1]).

-define(AUTH, auth_subscription).
-define(SUB, subscription_data).
-define(REG, access_registration).
-define(APN_KEY, <<"apn_config_profile">>).
-define(CAS_RETRIES, 100).

-type imsi() :: binary().
-type resource() :: #{binary() => term()}.

-doc "Store (create or replace) the authentication subscription for an IMSI.".
-spec put_authentication_subscription(imsi(), resource()) -> ok | {error, term()}.
put_authentication_subscription(Imsi, Sub) ->
    udr_db:put(?AUTH, Imsi, Sub).

-doc "Fetch the authentication subscription (Ki/OPc/algorithm/AMF/SQN) for an IMSI.".
-spec get_authentication_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_authentication_subscription(Imsi) ->
    case udr_db:get(?AUTH, Imsi) of
        {ok, Doc}              -> {ok, strip_meta(Doc)};
        {error, not_found} = E -> E
    end.

%% Remove udr_db-internal storage keys from a returned domain resource.
-spec strip_meta(resource()) -> resource().
strip_meta(Doc) ->
    maps:without([<<"version">>, <<"_id">>], Doc).

-doc "Atomically reserve a block of N consecutive SQNs; returns the first (start) SQN.\n"
     "Reads the current SQN/version and CAS-increments SQN by N, retrying on a concurrent\n"
     "version conflict. The caller generates vectors for [Start, Start+N).".
-spec advance_sqn(imsi(), pos_integer()) ->
    {ok, non_neg_integer()} | {error, not_found} | {error, cas_exhausted}.
advance_sqn(Imsi, N) ->
    advance_sqn(Imsi, N, ?CAS_RETRIES).

advance_sqn(_Imsi, _N, 0) ->
    {error, cas_exhausted};
advance_sqn(Imsi, N, Tries) ->
    case udr_db:get(?AUTH, Imsi) of
        {error, not_found} ->
            {error, not_found};
        {ok, #{<<"sqn">> := Start, <<"version">> := V}} ->
            case udr_db:update(?AUTH, Imsi, V, #{inc => #{<<"sqn">> => N}}) of
                {ok, _New}                -> {ok, Start};
                {error, version_conflict} -> advance_sqn(Imsi, N, Tries - 1);
                {error, not_found}        -> {error, not_found}
            end
    end.

-doc "Repair the stored SQN to the supplied value after an AUTS resync (CAS, retried on conflict). Callers pass SQN_MS + 1 (the next SQN to allocate).".
-spec repair_sqn(imsi(), non_neg_integer()) ->
    ok | {error, not_found} | {error, cas_exhausted}.
repair_sqn(Imsi, SqnMs) ->
    repair_sqn(Imsi, SqnMs, ?CAS_RETRIES).

repair_sqn(_Imsi, _SqnMs, 0) ->
    {error, cas_exhausted};
repair_sqn(Imsi, SqnMs, Tries) ->
    case udr_db:get(?AUTH, Imsi) of
        {error, not_found} ->
            {error, not_found};
        {ok, #{<<"version">> := V}} ->
            case udr_db:update(?AUTH, Imsi, V, #{set => #{<<"sqn">> => SqnMs}}) of
                {ok, _New}                -> ok;
                {error, version_conflict} -> repair_sqn(Imsi, SqnMs, Tries - 1);
                {error, not_found}        -> {error, not_found}
            end
    end.

-doc "Store (create or replace) the EPS subscription profile for an IMSI.".
-spec put_subscription_data(imsi(), resource()) -> ok | {error, term()}.
put_subscription_data(Imsi, Profile) ->
    udr_db:put(?SUB, Imsi, Profile).

-doc "The full EPS subscription profile (AM + SM) for an IMSI, in one read.".
-spec get_subscription_data(imsi()) -> {ok, resource()} | {error, not_found}.
get_subscription_data(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc}              -> {ok, strip_meta(Doc)};
        {error, not_found} = E -> E
    end.

-doc "Access-and-Mobility subscription data (profile minus the APN config profile).".
-spec get_am_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_am_subscription(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc}              -> {ok, maps:remove(?APN_KEY, strip_meta(Doc))};
        {error, not_found} = E -> E
    end.

-doc "Session-Management subscription data (just the APN config profile).".
-spec get_sm_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_sm_subscription(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc}              -> {ok, maps:with([?APN_KEY], strip_meta(Doc))};
        {error, not_found} = E -> E
    end.

-doc "Fetch the current 3GPP (serving-MME) registration for an IMSI.".
-spec get_3gpp_access_registration(imsi()) -> {ok, resource()} | {error, not_registered}.
get_3gpp_access_registration(Imsi) ->
    case udr_db:get(?REG, Imsi) of
        {ok, Doc}          -> {ok, strip_meta(Doc)};
        {error, not_found} -> {error, not_registered}
    end.

-doc "Store (create or replace) the 3GPP access registration for an IMSI.".
-spec put_3gpp_access_registration(imsi(), resource()) -> ok | {error, term()}.
put_3gpp_access_registration(Imsi, Reg) ->
    udr_db:put(?REG, Imsi, Reg).

-doc "Delete (clear) the 3GPP access registration for an IMSI (purge).".
-spec delete_3gpp_access_registration(imsi()) -> ok | {error, term()}.
delete_3gpp_access_registration(Imsi) ->
    udr_db:delete(?REG, Imsi).
