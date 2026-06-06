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
-moduledoc "Backend-agnostic conformance scenarios for any `udr_db_backend`.\n"
           "Run through the `udr_db` facade against a configured + started backend.".
-include_lib("eunit/include/eunit.hrl").

-export([scenarios/0]).

-doc "Return the list of {Name, Fun/0} conformance scenarios.".
-spec scenarios() -> [{string(), fun(() -> any())}].
scenarios() ->
    [
     {"put initializes version=1 and get round-trips",
      fun() ->
          ok = udr_db:put(c, <<"k1">>, #{<<"a">> => 1}),
          {ok, D} = udr_db:get(c, <<"k1">>),
          ?assertEqual(1, maps:get(<<"a">>, D)),
          ?assertEqual(1, maps:get(<<"version">>, D))
      end},
     {"get missing returns not_found",
      fun() -> ?assertEqual({error, not_found}, udr_db:get(c, <<"missing">>)) end},
     {"put replaces an existing doc",
      fun() ->
          ok = udr_db:put(c, <<"k2">>, #{<<"a">> => 1}),
          ok = udr_db:put(c, <<"k2">>, #{<<"b">> => 2}),
          {ok, D} = udr_db:get(c, <<"k2">>),
          ?assertEqual(error, maps:find(<<"a">>, D)),   %% old field gone (full replace)
          ?assertEqual(2, maps:get(<<"b">>, D)),
          ?assertEqual(1, maps:get(<<"version">>, D))   %% put always resets version to 1
      end},
     {"delete removes the doc",
      fun() ->
          ok = udr_db:put(c, <<"k3">>, #{<<"a">> => 1}),
          ok = udr_db:delete(c, <<"k3">>),
          ?assertEqual({error, not_found}, udr_db:get(c, <<"k3">>))
      end},
     {"find matches by selector equality",
      fun() ->
          ok = udr_db:put(c, <<"k4">>, #{<<"m">> => <<"x">>}),
          ok = udr_db:put(c, <<"k5">>, #{<<"m">> => <<"y">>}),
          {ok, Docs} = udr_db:find(c, #{<<"m">> => <<"x">>}),
          ?assertEqual(1, length(Docs))
      end},
     {"find returns all matching docs (multi-match)",
      fun() ->
          ok = udr_db:put(c, <<"k4a">>, #{<<"m">> => <<"z">>}),
          ok = udr_db:put(c, <<"k4b">>, #{<<"m">> => <<"z">>}),
          ok = udr_db:put(c, <<"k4c">>, #{<<"m">> => <<"q">>}),
          {ok, Docs} = udr_db:find(c, #{<<"m">> => <<"z">>}),
          ?assertEqual(2, length(Docs)),
          ?assert(lists:all(fun(D) -> maps:get(<<"m">>, D) =:= <<"z">> end, Docs))
      end},
     {"update CAS: matching version applies set+inc, bumps version",
      fun() ->
          ok = udr_db:put(c, <<"k6">>, #{<<"sqn">> => 10, <<"s">> => <<"a">>}),
          {ok, New} = udr_db:update(c, <<"k6">>, 1,
                                    #{set => #{<<"s">> => <<"b">>}, inc => #{<<"sqn">> => 5}}),
          ?assertEqual(15, maps:get(<<"sqn">>, New)),
          ?assertEqual(<<"b">>, maps:get(<<"s">>, New)),
          ?assertEqual(2, maps:get(<<"version">>, New))
      end},
     {"update CAS: stale version returns version_conflict, no mutation",
      fun() ->
          ok = udr_db:put(c, <<"k7">>, #{<<"sqn">> => 10}),
          ?assertEqual({error, version_conflict},
                       udr_db:update(c, <<"k7">>, 7, #{inc => #{<<"sqn">> => 1}})),
          {ok, D} = udr_db:get(c, <<"k7">>),
          ?assertEqual(10, maps:get(<<"sqn">>, D))
      end},
     {"update CAS: missing key returns not_found",
      fun() ->
          ?assertEqual({error, not_found},
                       udr_db:update(c, <<"nope">>, 1, #{inc => #{<<"sqn">> => 1}}))
      end}
    ].
