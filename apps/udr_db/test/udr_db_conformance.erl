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
-module(udr_db_conformance).
-moduledoc "Backend-agnostic conformance scenarios for any `udr_db_backend` implementation.\n"
           "Covers all scenarios mandated by database.md §8.1.\n"
           "\n"
           "Usage: call `scenarios(Backend, Coll, IdxColl)` where:\n"
           "  `Backend`  — the module implementing `udr_db_backend` (e.g. `udr_db_mnesia`)\n"
           "  `Coll`     — a collection atom (no indexes) already created via `ensure_collection`\n"
           "  `IdxColl`  — a collection atom with `#{indexes => [<<\"idx\">>]}` already created\n"
           "\n"
           "Each scenario is a `{Name::string(), fun/0}` pair that asserts exact return values\n"
           "and is self-contained (uses unique keys, makes no assumptions about prior state).".
-include_lib("eunit/include/eunit.hrl").

-export([scenarios/3]).

-doc "Return the list of `{Name, Fun/0}` conformance scenarios.\n"
     "`Backend` is called directly (not via the facade).".
-spec scenarios(module(), atom(), atom()) -> [{string(), fun(() -> any())}].
scenarios(B, Coll, IdxColl) ->
    [
     %% ---- CRUD ----
     {"put returns {ok, 1} for a new key",
      fun() ->
          {ok, V} = B:put(Coll, <<"crud_put_new">>, #{<<"a">> => 1}),
          ?assertEqual(1, V)
      end},

     {"put upserts and bumps version",
      fun() ->
          {ok, V1} = B:put(Coll, <<"crud_put_upsert">>, #{<<"a">> => 1}),
          ?assertEqual(1, V1),
          {ok, V2} = B:put(Coll, <<"crud_put_upsert">>, #{<<"a">> => 2}),
          ?assertEqual(2, V2)
      end},

     {"get round-trips doc without version in doc body",
      fun() ->
          {ok, _} = B:put(Coll, <<"crud_get">>, #{<<"x">> => 42}),
          {ok, Doc, Vsn} = B:get(Coll, <<"crud_get">>),
          ?assertEqual(42, maps:get(<<"x">>, Doc)),
          ?assertEqual(1, Vsn),
          %% version is metadata, never a doc field
          ?assertEqual(error, maps:find(<<"version">>, Doc)),
          %% _id is storage metadata, must be stripped from returned doc
          ?assertEqual(error, maps:find(<<"_id">>, Doc))
      end},

     {"get missing key returns {error, not_found}",
      fun() ->
          ?assertEqual({error, not_found}, B:get(Coll, <<"crud_get_missing">>))
      end},

     {"delete removes doc",
      fun() ->
          {ok, _} = B:put(Coll, <<"crud_del">>, #{<<"a">> => 1}),
          ok = B:delete(Coll, <<"crud_del">>),
          ?assertEqual({error, not_found}, B:get(Coll, <<"crud_del">>))
      end},

     {"delete is idempotent on absent key",
      fun() ->
          ok = B:delete(Coll, <<"crud_del_absent">>),
          ok = B:delete(Coll, <<"crud_del_absent">>)
      end},

     {"delete is idempotent on already-deleted key",
      fun() ->
          {ok, _} = B:put(Coll, <<"crud_del_idem">>, #{<<"a">> => 1}),
          ok = B:delete(Coll, <<"crud_del_idem">>),
          ok = B:delete(Coll, <<"crud_del_idem">>)
      end},

     {"find returns matching docs by selector equality",
      fun() ->
          {ok, _} = B:put(Coll, <<"find_k1">>, #{<<"m">> => <<"x">>}),
          {ok, _} = B:put(Coll, <<"find_k2">>, #{<<"m">> => <<"y">>}),
          {ok, _} = B:put(Coll, <<"find_k3">>, #{<<"m">> => <<"x">>}),
          {ok, Docs} = B:find(Coll, #{<<"m">> => <<"x">>}),
          Vals = [maps:get(<<"m">>, D) || D <- Docs,
                  maps:get(<<"m">>, D, undefined) =:= <<"x">>],
          ?assertEqual(2, length(Vals))
      end},

     {"find returns empty list when no match",
      fun() ->
          {ok, Docs} = B:find(Coll, #{<<"find_none_sentinel">> => <<"z99">>}),
          ?assertEqual([], Docs)
      end},

     %% ---- cas_put ----
     {"cas_put succeeds when version matches and bumps version",
      fun() ->
          {ok, 1} = B:put(Coll, <<"cas_match">>, #{<<"v">> => 1}),
          {ok, Doc0, 1} = B:get(Coll, <<"cas_match">>),
          {ok, V2} = B:cas_put(Coll, <<"cas_match">>, 1, Doc0#{<<"v">> => 2}),
          ?assertEqual(2, V2),
          {ok, Doc1, V3} = B:get(Coll, <<"cas_match">>),
          ?assertEqual(2, V3),
          ?assertEqual(2, maps:get(<<"v">>, Doc1))
      end},

     {"cas_put returns {error, version_conflict} on stale version",
      fun() ->
          {ok, _} = B:put(Coll, <<"cas_stale">>, #{<<"v">> => 1}),
          ?assertEqual({error, version_conflict},
                       B:cas_put(Coll, <<"cas_stale">>, 99, #{<<"v">> => 2})),
          %% doc must be unchanged
          {ok, Doc, 1} = B:get(Coll, <<"cas_stale">>),
          ?assertEqual(1, maps:get(<<"v">>, Doc))
      end},

     {"cas_put returns {error, not_found} for absent key",
      fun() ->
          ?assertEqual({error, not_found},
                       B:cas_put(Coll, <<"cas_absent">>, 1, #{<<"v">> => 1}))
      end},

     %% ---- take ----
     {"take returns {ok, Doc, Vsn} and removes the doc",
      fun() ->
          {ok, _} = B:put(Coll, <<"take_k">>, #{<<"t">> => 1}),
          {ok, Doc, Vsn} = B:take(Coll, <<"take_k">>),
          ?assertEqual(1, maps:get(<<"t">>, Doc)),
          ?assertEqual(1, Vsn),
          ?assertEqual({error, not_found}, B:get(Coll, <<"take_k">>)),
          %% _id is storage metadata, must be stripped from returned doc
          ?assertEqual(error, maps:find(<<"_id">>, Doc))
      end},

     {"take on absent key returns {error, not_found}",
      fun() ->
          ?assertEqual({error, not_found}, B:take(Coll, <<"take_absent">>))
      end},

     {"take is atomic: second take returns not_found",
      fun() ->
          {ok, _} = B:put(Coll, <<"take_double">>, #{<<"t">> => 2}),
          {ok, _, _} = B:take(Coll, <<"take_double">>),
          ?assertEqual({error, not_found}, B:take(Coll, <<"take_double">>))
      end},

     %% ---- find_by (indexed collection) ----
     {"find_by returns docs matching the declared index value",
      fun() ->
          {ok, _} = B:put(IdxColl, <<"fb_k1">>, #{<<"idx">> => <<"v1">>, <<"d">> => 1}),
          {ok, _} = B:put(IdxColl, <<"fb_k2">>, #{<<"idx">> => <<"v2">>, <<"d">> => 2}),
          {ok, _} = B:put(IdxColl, <<"fb_k3">>, #{<<"idx">> => <<"v1">>, <<"d">> => 3}),
          {ok, Docs} = B:find_by(IdxColl, <<"idx">>, <<"v1">>),
          ?assertEqual(2, length(Docs)),
          ?assert(lists:all(fun(D) -> maps:get(<<"idx">>, D) =:= <<"v1">> end, Docs))
      end},

     {"find_by returns empty list when no match",
      fun() ->
          {ok, Docs} = B:find_by(IdxColl, <<"idx">>, <<"no_such_value">>),
          ?assertEqual([], Docs)
      end},

     {"find_by returns error for undeclared index",
      fun() ->
          ?assertEqual({error, undeclared_index},
                       B:find_by(IdxColl, <<"not_declared">>, <<"x">>))
      end},

     %% ---- fold ----
     {"fold iterates all matching docs",
      fun() ->
          {ok, _} = B:put(Coll, <<"fold_k1">>, #{<<"grp">> => <<"g1">>, <<"n">> => 1}),
          {ok, _} = B:put(Coll, <<"fold_k2">>, #{<<"grp">> => <<"g1">>, <<"n">> => 2}),
          {ok, _} = B:put(Coll, <<"fold_k3">>, #{<<"grp">> => <<"g2">>, <<"n">> => 3}),
          {ok, Sum} = B:fold(Coll, #{<<"grp">> => <<"g1">>},
                             fun(Doc, Acc) -> Acc + maps:get(<<"n">>, Doc) end, 0),
          ?assertEqual(3, Sum)
      end},

     {"fold over empty match returns initial accumulator",
      fun() ->
          {ok, Acc} = B:fold(Coll, #{<<"fold_none_sentinel">> => <<"zzz">>},
                             fun(_Doc, A) -> A + 1 end, 0),
          ?assertEqual(0, Acc)
      end},

     %% ---- count ----
     {"count returns number of matching docs",
      fun() ->
          {ok, _} = B:put(Coll, <<"cnt_k1">>, #{<<"cg">> => <<"c1">>}),
          {ok, _} = B:put(Coll, <<"cnt_k2">>, #{<<"cg">> => <<"c1">>}),
          {ok, _} = B:put(Coll, <<"cnt_k3">>, #{<<"cg">> => <<"c2">>}),
          {ok, N1} = B:count(Coll, #{<<"cg">> => <<"c1">>}),
          ?assertEqual(2, N1),
          {ok, N2} = B:count(Coll, #{<<"cg">> => <<"c2">>}),
          ?assertEqual(1, N2)
      end},

     {"count returns 0 for empty result",
      fun() ->
          {ok, N} = B:count(Coll, #{<<"count_none_sentinel">> => <<"zzz">>}),
          ?assertEqual(0, N)
      end}
    ].
