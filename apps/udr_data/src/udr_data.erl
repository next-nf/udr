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
           "maps with binary keys; the CAS `version` token is metadata — hidden from\n"
           "domain callers. Reads hand the raw doc to the aggregate accessor's `from_doc/1`;\n"
           "writes call `to_doc/1` before storing. CAS updates use `udr_db:update/3`\n"
           "with accessor-supplied Funs.".

-export([ensure_collections/0,
         put_authentication_subscription/2, get_authentication_subscription/1,
         delete_authentication_subscription/1,
         advance_sqn/2, repair_sqn/2,
         put_subscription_data/2, get_subscription_data/1,
         delete_subscription_data/1,
         get_am_subscription/1, get_sm_subscription/1,
         get_3gpp_access_registration/1, put_3gpp_access_registration/2,
         delete_3gpp_access_registration/1,
         registered_serving_nodes/0]).

-define(AUTH, auth_subscription).
-define(SUB,  subscription_data).
-define(REG,  access_registration).

-type imsi()     :: binary().
-type resource() :: #{binary() => term()}.

%%------------------------------------------------------------------------------
%% Collection bootstrap
%%------------------------------------------------------------------------------

-doc "Declare all udr_data collections. Call at application start (before\n"
     "listeners open) so every collection exists. Idempotent — safe to call\n"
     "multiple times.".
-spec ensure_collections() -> ok.
ensure_collections() ->
    ok = udr_db:ensure_collection(?AUTH, #{}),
    ok = udr_db:ensure_collection(?SUB,  #{}),
    ok = udr_db:ensure_collection(?REG,  #{}).

%%------------------------------------------------------------------------------
%% auth_subscription
%%------------------------------------------------------------------------------

-doc "Store (create or replace) the authentication subscription for an IMSI.".
-spec put_authentication_subscription(imsi(), resource()) -> ok.
put_authentication_subscription(Imsi, Sub) ->
    {ok, _V} = udr_db:put(?AUTH, Imsi, udr_auth:to_doc(Sub)),
    ok.

-doc "Fetch the authentication subscription (Ki/OPc/algorithm/AMF/SQN) for an IMSI.".
-spec get_authentication_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_authentication_subscription(Imsi) ->
    case udr_db:get(?AUTH, Imsi) of
        {ok, Doc, _V}      -> {ok, udr_auth:from_doc(Doc)};
        {error, not_found} = E -> E
    end.

-doc "Delete the authentication subscription for an IMSI.".
-spec delete_authentication_subscription(imsi()) -> ok.
delete_authentication_subscription(Imsi) ->
    udr_db:delete(?AUTH, Imsi).

%%------------------------------------------------------------------------------
%% SQN management (CAS via update/3)
%%------------------------------------------------------------------------------

-doc "Atomically reserve a block of N consecutive SQNs; returns the first (start) SQN.\n"
     "Uses `udr_db:update/3` with `udr_auth:advance_sqn_fun/1` — no manual CAS loop.\n"
     "The reserved block is [Start, Start+N). The caller generates AUTN vectors for\n"
     "each SQN in that range.".
-spec advance_sqn(imsi(), pos_integer()) ->
    {ok, non_neg_integer()} | {error, not_found} | {error, cas_exhausted}.
advance_sqn(Imsi, N) ->
    case udr_db:update(?AUTH, Imsi, udr_auth:advance_sqn_fun(N)) of
        {ok, NewDoc, _V} ->
            Start = maps:get(<<"sqn">>, NewDoc) - N,
            {ok, Start};
        {error, not_found}  -> {error, not_found};
        {error, max_retries} -> {error, cas_exhausted}
    end.

-doc "Repair the stored SQN to the supplied value after an AUTS resync.\n"
     "Uses `udr_db:update/3` with `udr_auth:repair_sqn_fun/1`. Callers pass\n"
     "SQN_MS + 1 (the next SQN to allocate).".
-spec repair_sqn(imsi(), non_neg_integer()) ->
    ok | {error, not_found} | {error, cas_exhausted}.
repair_sqn(Imsi, SqnMs) ->
    case udr_db:update(?AUTH, Imsi, udr_auth:repair_sqn_fun(SqnMs)) of
        {ok, _, _}           -> ok;
        {error, not_found}   -> {error, not_found};
        {error, max_retries} -> {error, cas_exhausted}
    end.

%%------------------------------------------------------------------------------
%% subscription_data
%%------------------------------------------------------------------------------

-doc "Store (create or replace) the EPS subscription profile for an IMSI.".
-spec put_subscription_data(imsi(), resource()) -> ok.
put_subscription_data(Imsi, Profile) ->
    {ok, _V} = udr_db:put(?SUB, Imsi, udr_subscription:to_doc(Profile)),
    ok.

-doc "The full EPS subscription profile (AM + SM) for an IMSI, in one read.".
-spec get_subscription_data(imsi()) -> {ok, resource()} | {error, not_found}.
get_subscription_data(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc, _V}          -> {ok, udr_subscription:from_doc(Doc)};
        {error, not_found} = E -> E
    end.

-doc "Delete the EPS subscription profile for an IMSI.".
-spec delete_subscription_data(imsi()) -> ok.
delete_subscription_data(Imsi) ->
    udr_db:delete(?SUB, Imsi).

-doc "Access-and-Mobility subscription data (profile minus the APN config profile).".
-spec get_am_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_am_subscription(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc, _V}          -> {ok, udr_subscription:am_view(udr_subscription:from_doc(Doc))};
        {error, not_found} = E -> E
    end.

-doc "Session-Management subscription data (just the APN config profile).".
-spec get_sm_subscription(imsi()) -> {ok, resource()} | {error, not_found}.
get_sm_subscription(Imsi) ->
    case udr_db:get(?SUB, Imsi) of
        {ok, Doc, _V}          -> {ok, udr_subscription:sm_view(udr_subscription:from_doc(Doc))};
        {error, not_found} = E -> E
    end.

%%------------------------------------------------------------------------------
%% access_registration
%%------------------------------------------------------------------------------

-doc "Fetch the current 3GPP (serving-MME) registration for an IMSI.".
-spec get_3gpp_access_registration(imsi()) -> {ok, resource()} | {error, not_registered}.
get_3gpp_access_registration(Imsi) ->
    case udr_db:get(?REG, Imsi) of
        {ok, Doc, _V}      -> {ok, udr_registration:from_doc(Doc)};
        {error, not_found} -> {error, not_registered}
    end.

-doc "Store (create or replace) the 3GPP access registration for an IMSI.".
-spec put_3gpp_access_registration(imsi(), resource()) -> ok.
put_3gpp_access_registration(Imsi, Reg) ->
    {ok, _V} = udr_db:put(?REG, Imsi, udr_registration:to_doc(Reg)),
    ok.

-doc "Delete (clear) the 3GPP access registration for an IMSI (purge).".
-spec delete_3gpp_access_registration(imsi()) -> ok.
delete_3gpp_access_registration(Imsi) ->
    udr_db:delete(?REG, Imsi).

-doc "Distinct, non-purged serving nodes (Host, Realm) across all 3GPP access\n"
     "registrations. Performs a full streaming traversal of the access_registration\n"
     "collection (a rare HSS Reset-path operation — not an indexed lookup).\n"
     "Accumulates distinct {Host, Realm} tuples for non-purged registrations into\n"
     "a set, then returns a sorted list. Infrastructure errors surface as\n"
     "`{error, Reason}`.".
-spec registered_serving_nodes() -> {ok, [{binary(), binary()}]} | {error, term()}.
registered_serving_nodes() ->
    FoldFun = fun(Doc, Acc) ->
        Reg = udr_registration:from_doc(Doc),
        case udr_registration:is_purged(Reg) of
            true  -> Acc;
            false ->
                case udr_registration:serving_mme(Reg) of
                    undefined -> Acc;
                    Identity  -> sets:add_element(Identity, Acc)
                end
        end
    end,
    try udr_db:fold(?REG, #{}, FoldFun, sets:new([{version, 2}])) of
        {ok, NodeSet} ->
            {ok, lists:sort(sets:to_list(NodeSet))}
    catch
        error:Reason -> {error, Reason};
        exit:Reason  -> {error, Reason}
    end.
