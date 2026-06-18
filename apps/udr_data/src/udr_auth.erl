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
-module(udr_auth).
-moduledoc "Accessor module for the `auth_subscription` aggregate.\n"
           "\n"
           "Owns the document shape (`from_doc/1`, `to_doc/1`), binary field-name\n"
           "literals, defaults for optional fields, upgrade-on-read for older\n"
           "`schema_version` values, and the invariant Funs used by `update/3`.\n"
           "\n"
           "**SQN Funs for `update/3`:**\n"
           "- `advance_sqn_fun(N)` — increments `<<\"sqn\">>` by N and returns\n"
           "  `{ok, NewDoc}`. The caller derives the reserved block start by matching\n"
           "  the `<<\"sqn\">>` field of the doc returned by `update/3`\n"
           "  (`#{<<\"sqn\">> := Sqn}`) and computing `Start = Sqn - N`.\n"
           "- `repair_sqn_fun(Sqn)` — sets `<<\"sqn\">>` to the given value.\n"
           "\n"
           "Aggregate fields (current schema_version = 1):\n"
           "- `<<\"ki\">>` — subscriber key (binary)\n"
           "- `<<\"opc\">>` — operator variant (binary)\n"
           "- `<<\"algorithm\">>` — authentication algorithm (binary, default `<<\"milenage\">>`)\n"
           "- `<<\"amf\">>` — authentication management field (binary, default `<<>>`)\n"
           "- `<<\"sqn\">>` — sequence number (non_neg_integer, default 0)\n"
           "- `<<\"schema_version\">>` — document schema version (pos_integer, always 1)".

-export([from_doc/1, to_doc/1]).
-export([advance_sqn_fun/1, repair_sqn_fun/1]).

-define(SCHEMA_VERSION, 1).

%% Binary field-name literals — all field names centralised here.
-define(F_SCHEMA_VERSION, <<"schema_version">>).
-define(F_KI,             <<"ki">>).
-define(F_OPC,            <<"opc">>).
-define(F_ALGORITHM,      <<"algorithm">>).
-define(F_AMF,            <<"amf">>).
-define(F_SQN,            <<"sqn">>).

-type doc()          :: #{binary() => term()}.
-type auth_map()     :: #{binary() => term()}.
-type update_fun()   :: fun((doc()) -> {ok, doc()} | {abort, term()}).

-export_type([doc/0, auth_map/0, update_fun/0]).

%%------------------------------------------------------------------------------
%% Public API
%%------------------------------------------------------------------------------

-doc "Convert a stored document to a typed auth map with defaults.\n"
     "Older `schema_version` values (or absent) are upgraded in-memory;\n"
     "the next `update/3` write will persist the new shape.\n"
     "Known fields are normalised with canonical defaults; unknown fields are\n"
     "passed through unchanged so callers that store extra data can read it\n"
     "back without loss.".
-spec from_doc(doc()) -> auth_map().
from_doc(Doc) ->
    Doc1 = upgrade(Doc),
    %% Defaults for the canonical schema fields; merge lets the (upgraded) stored
    %% doc win, so present fields — known or unknown — are preserved and only
    %% absent ones fall back to their default. `upgrade/1` normalises
    %% schema_version, so the merge can never retain a stale version.
    Init = #{ ?F_SCHEMA_VERSION => ?SCHEMA_VERSION,
              ?F_KI             => <<>>,
              ?F_OPC            => <<>>,
              ?F_ALGORITHM      => <<"milenage">>,
              ?F_AMF            => <<>>,
              ?F_SQN            => 0 },
    maps:merge(Init, Doc1).

-doc "Convert a typed auth map to a stored document, stamping `schema_version => 1`.".
-spec to_doc(auth_map()) -> doc().
to_doc(Map) ->
    Map#{ ?F_SCHEMA_VERSION => ?SCHEMA_VERSION }.

-doc "Returns a Fun suitable for `update/3` that increments `<<\"sqn\">>` by N.\n"
     "When `update/3` succeeds it returns `{ok, NewDoc, _Version}`; the caller\n"
     "derives the reserved block start by matching `#{<<\"sqn\">> := Sqn}` from\n"
     "`NewDoc` and computing `Start = Sqn - N`.".
-spec advance_sqn_fun(pos_integer()) -> update_fun().
advance_sqn_fun(N) ->
    fun(#{?F_SQN := Sqn} = Doc) ->
            {ok, Doc#{?F_SQN := Sqn + N}};
       (Doc) ->
            %% sqn absent — same as advancing from the implicit 0.
            {ok, Doc#{?F_SQN => N}}
    end.

-doc "Returns a Fun suitable for `update/3` that sets `<<\"sqn\">>` to Sqn.".
-spec repair_sqn_fun(non_neg_integer()) -> update_fun().
repair_sqn_fun(Sqn) ->
    fun(#{?F_SQN := _} = Doc) ->
            {ok, Doc#{?F_SQN := Sqn}};
       (Doc) ->
            {ok, Doc#{?F_SQN => Sqn}}
    end.

%%------------------------------------------------------------------------------
%% Internal helpers
%%------------------------------------------------------------------------------

%% upgrade/1 — upgrade-on-read for older or absent schema_version values.
%% Current version is 1; there is nothing to migrate from pre-v1 documents other
%% than filling in defaults (handled by from_doc/1). Add migration clauses here
%% when the schema advances past version 1.
-spec upgrade(doc()) -> doc().
upgrade(#{?F_SCHEMA_VERSION := ?SCHEMA_VERSION} = Doc) ->
    %% Already current — no migration needed.
    Doc;
upgrade(Doc) ->
    %% schema_version absent or older: treat as pre-v1 and let from_doc/1 apply
    %% defaults. Stamp the current version here so `from_doc/1`'s `maps:merge`
    %% retains the normalised version rather than a stale stored one. The stamped
    %% schema_version is also written back on the next update/3 call.
    Doc#{?F_SCHEMA_VERSION => ?SCHEMA_VERSION}.
