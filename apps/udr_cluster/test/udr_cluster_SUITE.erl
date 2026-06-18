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
-module(udr_cluster_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([runs_fun_returns_result_and_releases_lock/1,
         second_acquirer_times_out_with_session_busy_while_held/1,
         distinct_imsis_do_not_block_each_other/1,
         queue_then_proceed_waiter_acquires_after_holder_releases/1,
         lock_auto_releases_when_holder_process_killed/1,
         %% with_entity tests
         with_entity_acquire_run_release/1,
         with_entity_second_concurrent_returns_busy/1,
         with_entity_lock_released_after_fun_returns/1,
         with_entity_lock_auto_released_on_crash/1,
         with_entity_different_scopes_do_not_block/1,
         with_session_alias_delegates_to_udr_session_scope/1]).

-define(TEST_SCOPE, udr_test_entity).

all() ->
    [runs_fun_returns_result_and_releases_lock,
     second_acquirer_times_out_with_session_busy_while_held,
     distinct_imsis_do_not_block_each_other,
     queue_then_proceed_waiter_acquires_after_holder_releases,
     lock_auto_releases_when_holder_process_killed,
     with_entity_acquire_run_release,
     with_entity_second_concurrent_returns_busy,
     with_entity_lock_released_after_fun_returns,
     with_entity_lock_auto_released_on_crash,
     with_entity_different_scopes_do_not_block,
     with_session_alias_delegates_to_udr_session_scope].

init_per_testcase(_TestCase, Config) ->
    {ok, Started} = application:ensure_all_started(udr_cluster),
    %% Register the extra test scope for with_entity tests.
    ok = syn:add_node_to_scopes([?TEST_SCOPE]),
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    Started = ?config(started, Config),
    [ application:stop(A) || A <- lists:reverse(Started) ],
    ok.

wait_until(F) -> wait_until(F, 200).
wait_until(_F, 0) -> erlang:error(timeout);
wait_until(F, N) ->
    case F() of
        true  -> ok;
        false -> timer:sleep(10), wait_until(F, N - 1)
    end.

runs_fun_returns_result_and_releases_lock(_Config) ->
    ?assertEqual(42, udr_cluster:with_session(<<"i">>, fun() -> 42 end)),
    ?assertEqual(undefined, udr_cluster:whereis_session(<<"i">>)),
    ok.

second_acquirer_times_out_with_session_busy_while_held(_Config) ->
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_session(<<"i">>, fun() ->
            Parent ! acquired, receive release -> ok end
        end)
    end),
    receive acquired -> ok end,
    ?assertEqual({error, session_busy},
                 udr_cluster:with_session(<<"i">>, fun() -> 1 end, 100)),
    Holder ! release,
    wait_until(fun() -> udr_cluster:whereis_session(<<"i">>) =:= undefined end),
    ?assertEqual(ok, udr_cluster:with_session(<<"i">>, fun() -> ok end)),
    ok.

distinct_imsis_do_not_block_each_other(_Config) ->
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_session(<<"a">>, fun() ->
            Parent ! acquired, receive release -> ok end
        end)
    end),
    receive acquired -> ok end,
    ?assertEqual(ok, udr_cluster:with_session(<<"b">>, fun() -> ok end, 100)),
    Holder ! release,
    ok.

queue_then_proceed_waiter_acquires_after_holder_releases(_Config) ->
    Parent = self(),
    _Holder = spawn(fun() ->
        udr_cluster:with_session(<<"i">>, fun() ->
            Parent ! up, timer:sleep(50)
        end)
    end),
    receive up -> ok end,
    ?assertEqual(done, udr_cluster:with_session(<<"i">>, fun() -> done end, 2000)),
    ok.

lock_auto_releases_when_holder_process_killed(_Config) ->
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_session(<<"i">>, fun() ->
            Parent ! up, receive _ -> ok end
        end)
    end),
    receive up -> ok end,
    ?assert(is_pid(udr_cluster:whereis_session(<<"i">>))),
    exit(Holder, kill),
    wait_until(fun() -> udr_cluster:whereis_session(<<"i">>) =:= undefined end),
    ?assertEqual(ok, udr_cluster:with_session(<<"i">>, fun() -> ok end)),
    ok.

%% -------------------------------------------------------------------------
%% with_entity/3,4 tests
%% -------------------------------------------------------------------------

%% with_entity acquires the lock, runs the fun, returns its result, then releases.
with_entity_acquire_run_release(_Config) ->
    Key = <<"entity-1">>,
    Result = udr_cluster:with_entity(?TEST_SCOPE, Key, fun() -> hello end),
    ?assertEqual(hello, Result),
    %% Lock is released after fun returns.
    ?assertEqual(undefined, udr_cluster:whereis_entity(?TEST_SCOPE, Key)),
    ok.

%% A second concurrent acquire on the same (Scope, Key) returns {error, session_busy}.
with_entity_second_concurrent_returns_busy(_Config) ->
    Key = <<"entity-2">>,
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_entity(?TEST_SCOPE, Key, fun() ->
            Parent ! acquired, receive release -> ok end
        end)
    end),
    receive acquired -> ok end,
    %% A second attempt with a short timeout must fail.
    ?assertEqual({error, session_busy},
                 udr_cluster:with_entity(?TEST_SCOPE, Key, fun() -> 1 end, 100)),
    Holder ! release,
    wait_until(fun() -> udr_cluster:whereis_entity(?TEST_SCOPE, Key) =:= undefined end),
    ok.

%% Lock is released when Fun returns normally (verified by a subsequent acquire succeeding).
with_entity_lock_released_after_fun_returns(_Config) ->
    Key = <<"entity-3">>,
    ?assertEqual(first, udr_cluster:with_entity(?TEST_SCOPE, Key, fun() -> first end)),
    ?assertEqual(second, udr_cluster:with_entity(?TEST_SCOPE, Key, fun() -> second end)),
    ok.

%% Lock is auto-released when the holder process crashes.
with_entity_lock_auto_released_on_crash(_Config) ->
    Key = <<"entity-4">>,
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_entity(?TEST_SCOPE, Key, fun() ->
            Parent ! up, receive _ -> ok end
        end)
    end),
    receive up -> ok end,
    ?assert(is_pid(udr_cluster:whereis_entity(?TEST_SCOPE, Key))),
    exit(Holder, kill),
    wait_until(fun() -> udr_cluster:whereis_entity(?TEST_SCOPE, Key) =:= undefined end),
    %% After auto-release a new acquire must succeed.
    ?assertEqual(ok, udr_cluster:with_entity(?TEST_SCOPE, Key, fun() -> ok end)),
    ok.

%% Locks on different scopes are independent — one does not block the other.
with_entity_different_scopes_do_not_block(_Config) ->
    Key = <<"entity-5">>,
    Parent = self(),
    Holder = spawn(fun() ->
        udr_cluster:with_entity(?TEST_SCOPE, Key, fun() ->
            Parent ! acquired, receive release -> ok end
        end)
    end),
    receive acquired -> ok end,
    %% The same key under the udr_session scope must not be blocked.
    ?assertEqual(ok, udr_cluster:with_entity(udr_session, Key, fun() -> ok end, 100)),
    Holder ! release,
    ok.

%% with_session/2,3 delegates to the udr_session scope via with_entity.
with_session_alias_delegates_to_udr_session_scope(_Config) ->
    Imsi = <<"460001234567890">>,
    %% Basic delegation: result returned, lock released.
    ?assertEqual(aliased, udr_cluster:with_session(Imsi, fun() -> aliased end)),
    ?assertEqual(undefined, udr_cluster:whereis_session(Imsi)),
    %% Lock acquired under udr_session scope, visible via whereis_entity.
    Parent = self(),
    spawn(fun() ->
        udr_cluster:with_session(Imsi, fun() ->
            Parent ! up, receive release -> ok end
        end)
    end),
    receive up -> ok end,
    ?assert(is_pid(udr_cluster:whereis_entity(udr_session, Imsi))),
    ?assertEqual({error, session_busy},
                 udr_cluster:with_session(Imsi, fun() -> 1 end, 50)),
    %% Release via whereis_entity confirms same scope used.
    udr_cluster:whereis_entity(udr_session, Imsi) ! release,
    wait_until(fun() -> udr_cluster:whereis_session(Imsi) =:= undefined end),
    ok.
