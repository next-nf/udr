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
-module(udr_registration).
-moduledoc "Accessor module for the `access_registration` aggregate.\n"
           "\n"
           "Owns the document shape (`from_doc/1`, `to_doc/1`), binary field-name\n"
           "literals, defaults for optional fields, upgrade-on-read for older\n"
           "`schema_version` values, and domain helpers.\n"
           "\n"
           "Domain helpers:\n"
           "- `is_purged/1` — true iff `<<\"ue_purged\">>` is `true`.\n"
           "- `serving_mme/1` — extracts `{Host, Realm}` from a registration map,\n"
           "  or `undefined` when `<<\"serving_mme_host\">>` is absent.\n"
           "\n"
           "Aggregate fields (current schema_version = 1):\n"
           "- `<<\"serving_mme_host\">>` — serving MME host FQDN (binary, default `<<>>`)\n"
           "- `<<\"serving_mme_realm\">>` — serving MME realm (binary, default `<<>>`)\n"
           "- `<<\"ue_purged\">>` — UE purge flag (boolean, default false)\n"
           "- `<<\"status\">>` — registration status string (binary, default `<<>>`)\n"
           "- `<<\"schema_version\">>` — document schema version (pos_integer, always 1)".

-export([from_doc/1, to_doc/1]).
-export([is_purged/1, serving_mme/1]).

-define(SCHEMA_VERSION, 1).

%% Binary field-name literals — all field names centralised here.
-define(F_SCHEMA_VERSION,   <<"schema_version">>).
-define(F_SERVING_MME_HOST, <<"serving_mme_host">>).
-define(F_SERVING_MME_REALM, <<"serving_mme_realm">>).
-define(F_UE_PURGED,        <<"ue_purged">>).
-define(F_STATUS,           <<"status">>).

-type doc()              :: #{binary() => term()}.
-type registration_map() :: #{binary() => term()}.

-export_type([doc/0, registration_map/0]).

%%------------------------------------------------------------------------------
%% Public API
%%------------------------------------------------------------------------------

-doc "Convert a stored document to a typed registration map with defaults.\n"
     "Older `schema_version` values (or absent) are upgraded in-memory.\n"
     "Known fields are normalised with canonical defaults; unknown fields are\n"
     "passed through unchanged so callers that store extra data (e.g. `terminal_information`\n"
     "from a NOR request) can read it back without loss.".
-spec from_doc(doc()) -> registration_map().
from_doc(Doc) ->
    Doc1 = upgrade(Doc),
    %% Defaults for the canonical schema fields; merge lets the (upgraded) stored
    %% doc win, so present fields — known or unknown — are preserved and only
    %% absent ones fall back to their default. `upgrade/1` normalises
    %% schema_version, so the merge can never retain a stale version.
    Init = #{ ?F_SCHEMA_VERSION    => ?SCHEMA_VERSION,
              ?F_SERVING_MME_HOST  => <<>>,
              ?F_SERVING_MME_REALM => <<>>,
              ?F_UE_PURGED         => false,
              ?F_STATUS            => <<>> },
    maps:merge(Init, Doc1).

-doc "Convert a typed registration map to a stored document, stamping `schema_version => 1`.".
-spec to_doc(registration_map()) -> doc().
to_doc(Map) ->
    Map#{ ?F_SCHEMA_VERSION => ?SCHEMA_VERSION }.

-doc "Returns `true` iff `<<\"ue_purged\">>` is `true` in the registration map.".
-spec is_purged(registration_map()) -> boolean().
is_purged(#{?F_UE_PURGED := Purged}) when is_boolean(Purged) ->
    Purged;
is_purged(_Map) ->
    false.

-doc "Extracts the serving MME identity `{Host, Realm}` from a registration map.\n"
     "Returns `undefined` when `<<\"serving_mme_host\">>` is absent or empty.".
-spec serving_mme(registration_map()) ->
    {Host :: binary(), Realm :: binary()} | undefined.
serving_mme(#{?F_SERVING_MME_HOST := <<>>}) ->
    undefined;
serving_mme(#{?F_SERVING_MME_HOST := Host} = Map) ->
    {Host, maps:get(?F_SERVING_MME_REALM, Map, <<>>)};
serving_mme(_Map) ->
    undefined.

%%------------------------------------------------------------------------------
%% Internal helpers
%%------------------------------------------------------------------------------

%% upgrade/1 — upgrade-on-read for older or absent schema_version values.
%% Current version is 1; add migration clauses when the schema advances.
-spec upgrade(doc()) -> doc().
upgrade(#{?F_SCHEMA_VERSION := ?SCHEMA_VERSION} = Doc) ->
    Doc;
upgrade(Doc) ->
    %% schema_version absent or older: treat as pre-v1 and let from_doc/1 apply
    %% defaults. Stamp the current version here so `from_doc/1`'s `maps:merge`
    %% retains the normalised version rather than a stale stored one.
    Doc#{?F_SCHEMA_VERSION => ?SCHEMA_VERSION}.
