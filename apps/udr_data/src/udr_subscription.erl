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
-module(udr_subscription).
-moduledoc "Accessor module for the `subscription_data` aggregate.\n"
           "\n"
           "Owns the document shape (`from_doc/1`, `to_doc/1`), binary field-name\n"
           "literals, defaults for optional fields, and upgrade-on-read for older\n"
           "`schema_version` values.\n"
           "\n"
           "The aggregate covers the full EPS subscription profile used by HSS:\n"
           "- **AM view** (Access-and-Mobility): all fields except `<<\"apn_config_profile\">>`.\n"
           "  Retrieved via `am_view/1`.\n"
           "- **SM view** (Session-Management): only `<<\"apn_config_profile\">>` and\n"
           "  `<<\"schema_version\">>`. Retrieved via `sm_view/1`.\n"
           "\n"
           "Aggregate fields (current schema_version = 1):\n"
           "- `<<\"msisdn\">>` — MSISDN (binary, default `<<>>`)\n"
           "- `<<\"subscriber_status\">>` — status string (binary, default `<<\"SERVICE_GRANTED\">>`)\n"
           "- `<<\"ambr\">>` — aggregate max bit rate map (map, default `#{}`)\n"
           "- `<<\"apn_config_profile\">>` — APN config profile map (SM slice, default `#{}`)\n"
           "- `<<\"schema_version\">>` — document schema version (pos_integer, always 1)".

-export([from_doc/1, to_doc/1]).
-export([am_view/1, sm_view/1]).

-define(SCHEMA_VERSION, 1).

%% Binary field-name literals — all field names centralised here.
-define(F_SCHEMA_VERSION,    <<"schema_version">>).
-define(F_MSISDN,            <<"msisdn">>).
-define(F_SUBSCRIBER_STATUS, <<"subscriber_status">>).
-define(F_AMBR,              <<"ambr">>).
-define(F_APN_CONFIG_PROFILE, <<"apn_config_profile">>).

-type doc()           :: #{binary() => term()}.
-type subscription_map() :: #{binary() => term()}.

-export_type([doc/0, subscription_map/0]).

%%------------------------------------------------------------------------------
%% Public API
%%------------------------------------------------------------------------------

-doc "Convert a stored document to a typed subscription map with defaults.\n"
     "Older `schema_version` values (or absent) are upgraded in-memory.\n"
     "Known fields are normalised with canonical defaults; unknown fields are\n"
     "passed through unchanged so callers that store extra data (e.g. `iccid`\n"
     "from the provisioning API) can read it back without loss.".
-spec from_doc(doc()) -> subscription_map().
from_doc(Doc) ->
    Doc1 = upgrade(Doc),
    %% Start from the (possibly upgraded) doc to preserve unknown fields, then
    %% overlay the canonical schema fields with their defaults.
    Doc1#{ ?F_SCHEMA_VERSION     => ?SCHEMA_VERSION,
           ?F_MSISDN             => maps:get(?F_MSISDN,            Doc1, <<>>),
           ?F_SUBSCRIBER_STATUS  => maps:get(?F_SUBSCRIBER_STATUS, Doc1, <<"SERVICE_GRANTED">>),
           ?F_AMBR               => maps:get(?F_AMBR,              Doc1, #{}),
           ?F_APN_CONFIG_PROFILE => maps:get(?F_APN_CONFIG_PROFILE, Doc1, #{}) }.

-doc "Convert a typed subscription map to a stored document, stamping `schema_version => 1`.".
-spec to_doc(subscription_map()) -> doc().
to_doc(Map) ->
    Map#{ ?F_SCHEMA_VERSION => ?SCHEMA_VERSION }.

-doc "Access-and-Mobility view: the subscription map without `<<\"apn_config_profile\">>`.".
-spec am_view(subscription_map()) -> subscription_map().
am_view(Map) ->
    maps:remove(?F_APN_CONFIG_PROFILE, Map).

-doc "Session-Management view: only `<<\"schema_version\">>` and `<<\"apn_config_profile\">>`.".
-spec sm_view(subscription_map()) -> subscription_map().
sm_view(Map) ->
    maps:with([?F_SCHEMA_VERSION, ?F_APN_CONFIG_PROFILE], Map).

%%------------------------------------------------------------------------------
%% Internal helpers
%%------------------------------------------------------------------------------

%% upgrade/1 — upgrade-on-read for older or absent schema_version values.
%% Current version is 1; add migration clauses when the schema advances.
-spec upgrade(doc()) -> doc().
upgrade(#{?F_SCHEMA_VERSION := ?SCHEMA_VERSION} = Doc) ->
    Doc;
upgrade(Doc) ->
    %% schema_version absent or older: treat as pre-v1 and let from_doc/1
    %% apply defaults.
    Doc.
