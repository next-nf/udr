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
-module(udr_db_facade_SUITE).
-moduledoc "Common Test suite for the `udr_db` facade contract:\n"
           "`update/3` (success, abort, retry, max_retries),\n"
           "`create/3` (success, exists),\n"
           "`get/2`/`put/3` new return shapes,\n"
           "`ready/0`.\n"
           "Runs on Mnesia-ram via `udr_db_ct:setup_mnesia_ram/0`.".
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0,
         init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([get_put_shapes/1,
         update_success/1, update_abort/1, update_retry/1, update_max_retries/1,
         create_success/1, create_exists/1,
         ready_returns_boolean/1]).

-define(COLL, facade_test_coll).

all() ->
    [get_put_shapes,
     update_success, update_abort, update_retry, update_max_retries,
     create_success, create_exists,
     ready_returns_boolean].

%%--------------------------------------------------------------------
%% Suite lifecycle: set up Mnesia-ram once.
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    %% Reset the persistent_term cache so the new env is picked up.
    catch persistent_term:erase({udr_db, backend}),
    ok = udr_db_ct:setup_mnesia_ram(),
    {ok, _Pid} = udr_db_mnesia:start_link(#{}),
    ok = udr_db_mnesia:ensure_collection(?COLL, #{storage => ram_copies}),
    ok = udr_db_mnesia:wait_ready([?COLL]),
    Config.

end_per_suite(_Config) ->
    catch gen_server:stop(udr_db_mnesia),
    udr_db_ct:teardown_mnesia(),
    ok.

%%--------------------------------------------------------------------
%% Per-testcase: clear the collection so each test starts clean.
%%--------------------------------------------------------------------

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(?COLL),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

%% get/2 returns {ok, Doc, Version}; put/3 returns {ok, Version}.
%% Version is metadata — never a doc field.
get_put_shapes(_Config) ->
    {ok, V1} = udr_db:put(?COLL, <<"gps_k">>, #{<<"x">> => 42}),
    ?assertEqual(1, V1),
    {ok, Doc, Vsn} = udr_db:get(?COLL, <<"gps_k">>),
    ?assertEqual(42, maps:get(<<"x">>, Doc)),
    ?assertEqual(1, Vsn),
    %% version must NOT appear in the doc body
    ?assertEqual(error, maps:find(<<"version">>, Doc)),
    %% get on missing key
    ?assertEqual({error, not_found}, udr_db:get(?COLL, <<"gps_missing">>)),
    ok.

%% update/3 success: Fun edits doc, version bumps, returns {ok, NewDoc, NewVsn}.
update_success(_Config) ->
    {ok, _} = udr_db:put(?COLL, <<"upd_s">>, #{<<"n">> => 1}),
    Fun = fun(Doc) -> {ok, Doc#{<<"n">> => maps:get(<<"n">>, Doc) + 1}} end,
    {ok, NewDoc, NewVsn} = udr_db:update(?COLL, <<"upd_s">>, Fun),
    ?assertEqual(2, maps:get(<<"n">>, NewDoc)),
    ?assertEqual(2, NewVsn),
    %% verify persisted
    {ok, Got, _} = udr_db:get(?COLL, <<"upd_s">>),
    ?assertEqual(2, maps:get(<<"n">>, Got)),
    ok.

%% update/3 abort: Fun returns {abort, R} → {error, {aborted, R}}, doc unchanged.
update_abort(_Config) ->
    {ok, _} = udr_db:put(?COLL, <<"upd_ab">>, #{<<"n">> => 99}),
    Fun = fun(_Doc) -> {abort, nope} end,
    ?assertEqual({error, {aborted, nope}}, udr_db:update(?COLL, <<"upd_ab">>, Fun)),
    %% doc must be unchanged
    {ok, Doc, _} = udr_db:get(?COLL, <<"upd_ab">>),
    ?assertEqual(99, maps:get(<<"n">>, Doc)),
    ok.

%% update/3 not_found: returns {error, not_found}.
%% (Not strictly "retry" but verifies the not_found path.)

%% update/3 retry: verify that version_conflict triggers a retry and ultimate success.
%% Strategy: use a counter that starts at 0. We use cas_put to inject a conflict on
%% the first attempt by bumping the version externally before the Fun's result is
%% applied. We do this by having the Fun itself bump the version via a side-channel
%% on the first call only.
%%
%% Simpler: start a value=0, run update/3 that adds 10 in a Fun. Concurrently a
%% second process does a plain put to bump the version (causing conflict for the
%% first CAS attempt). After the second process completes, the update/3 should
%% retry, re-read the new doc, and produce n=10 (from the post-put value of 5, +10 =15).
update_retry(_Config) ->
    {ok, _} = udr_db:put(?COLL, <<"upd_r">>, #{<<"n">> => 0}),
    %% A counter that lets the Fun know whether it's the first or subsequent call.
    Counter = counters:new(1, []),
    Parent = self(),
    %% Spawn the updater. On the first Fun call it waits for the interleave signal.
    Updater = spawn_link(fun() ->
        Fun = fun(Doc) ->
            case counters:get(Counter, 1) of
                0 ->
                    counters:add(Counter, 1, 1),
                    %% Signal parent to interleave, then wait for clearance.
                    Parent ! first_call,
                    receive proceed -> ok end;
                _ ->
                    ok
            end,
            {ok, Doc#{<<"n">> => maps:get(<<"n">>, Doc) + 10}}
        end,
        Result = udr_db:update(?COLL, <<"upd_r">>, Fun),
        Parent ! {result, Result}
    end),
    receive first_call -> ok end,
    %% Bump the doc while the Fun is waiting — this will cause version_conflict.
    {ok, _} = udr_db:put(?COLL, <<"upd_r">>, #{<<"n">> => 5}),
    Updater ! proceed,
    Result = receive {result, R} -> R end,
    %% update/3 retried and succeeded. After re-read (n=5) Fun adds 10 → n=15.
    ?assertMatch({ok, _, _}, Result),
    {ok, Doc, _} = udr_db:get(?COLL, <<"upd_r">>),
    ?assertEqual(15, maps:get(<<"n">>, Doc)),
    ok.

%% update/3 max_retries: exhaust the retry budget via persistent conflicts.
%% Strategy: The Fun always returns {ok, Doc} so the only failure mode is
%% version_conflict. We trigger persistent conflicts by racing a loop that
%% continuously bumps the version while update/3 is trying to CAS.
%% With the default retry bound (100), we need the interleaver to stay ahead.
%% We use a tight loop in a high-priority process to reliably beat update/3.
%%
%% Alternative (simpler, deterministic): use the public update/3 with a Fun
%% that itself writes (via a side-channel) to bump the version every time, so
%% every CAS attempt conflicts.
update_max_retries(_Config) ->
    {ok, _} = udr_db:put(?COLL, <<"upd_mr">>, #{<<"x">> => 1}),
    Parent = self(),
    %% Fun that bumps the version via a plain put before returning the new doc,
    %% guaranteeing a conflict every iteration.  After 100 iterations, the
    %% facade returns max_retries.
    Fun = fun(Doc) ->
        %% Bump version — the subsequent cas_put will see version_conflict.
        {ok, _} = udr_db:put(?COLL, <<"upd_mr">>, Doc),
        {ok, Doc}
    end,
    spawn_link(fun() ->
        R = udr_db:update(?COLL, <<"upd_mr">>, Fun),
        Parent ! {result, R}
    end),
    Result = receive {result, R} -> R after 30000 -> timeout end,
    ?assertEqual({error, max_retries}, Result),
    ok.

%% create/3 success: insert-if-absent returns {ok, Version}.
create_success(_Config) ->
    {ok, V} = udr_db:create(?COLL, <<"cr_s">>, #{<<"a">> => 1}),
    ?assertEqual(1, V),
    {ok, Doc, _} = udr_db:get(?COLL, <<"cr_s">>),
    ?assertEqual(1, maps:get(<<"a">>, Doc)),
    ok.

%% create/3 exists: if the key already exists, returns {error, exists}.
create_exists(_Config) ->
    {ok, _} = udr_db:put(?COLL, <<"cr_e">>, #{<<"a">> => 1}),
    ?assertEqual({error, exists}, udr_db:create(?COLL, <<"cr_e">>, #{<<"a">> => 2})),
    %% original doc must be unchanged
    {ok, Doc, _} = udr_db:get(?COLL, <<"cr_e">>),
    ?assertEqual(1, maps:get(<<"a">>, Doc)),
    ok.

%% ready/0 returns a boolean.
ready_returns_boolean(_Config) ->
    Ready = udr_db:ready(),
    ?assert(is_boolean(Ready)),
    ok.
