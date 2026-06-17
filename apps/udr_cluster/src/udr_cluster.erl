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
-module(udr_cluster).
-moduledoc "Cluster-wide per-entity lock over `syn`. `with_entity/3,4` acquires an\n"
           "exclusive cluster-wide lock for a (Scope, Key) pair, runs Fun, then releases;\n"
           "the lock auto-releases on process death or node-down. `with_session/2,3` is a\n"
           "back-compat alias that fixes Scope to `udr_session` (the UDR per-IMSI scope).".

-export([scope/0,
         with_entity/3, with_entity/4,
         whereis_entity/2,
         with_session/2, with_session/3,
         whereis_session/1]).

-define(SCOPE, udr_session).
-define(DEFAULT_TIMEOUT, 5000).
-define(RETRY_INTERVAL, 25).

-doc "The default `syn` scope used for per-IMSI session locks.".
-spec scope() -> atom().
scope() ->
    ?SCOPE.

%% -------------------------------------------------------------------------
%% Generic with_entity/3,4
%% -------------------------------------------------------------------------

-doc "Run Fun while holding the cluster-wide lock for (Scope, Key),\n"
     "using the default 5 s acquire timeout.".
-spec with_entity(atom(), binary(), fun(() -> Result)) ->
    Result | {error, session_busy}.
with_entity(Scope, Key, Fun) ->
    with_entity(Scope, Key, Fun, ?DEFAULT_TIMEOUT).

-doc "Run Fun while holding the cluster-wide lock for (Scope, Key), waiting up to\n"
     "TimeoutMs milliseconds to acquire it (poll-with-deadline). Returns Fun's result,\n"
     "or {error, session_busy} on timeout. The lock is released when Fun returns or\n"
     "raises, and automatically if this process or its node dies.\n"
     "NOTE: Fun should not itself return {error, session_busy}.\n"
     "NOT re-entrant: Fun must not call with_entity for the SAME (Scope, Key) in the\n"
     "same process — syn would re-register the same pid and the inner release would drop\n"
     "the outer lock.".
-spec with_entity(atom(), binary(), fun(() -> Result), non_neg_integer()) ->
    Result | {error, session_busy}.
with_entity(Scope, Key, Fun, TimeoutMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    case acquire(Scope, Key, Deadline) of
        ok ->
            try Fun()
            after _ = syn:unregister(Scope, Key)
            end;
        {error, session_busy} = E ->
            E
    end.

-doc "Pid currently holding the lock for (Scope, Key), or undefined.".
-spec whereis_entity(atom(), binary()) -> pid() | undefined.
whereis_entity(Scope, Key) ->
    case syn:lookup(Scope, Key) of
        {Pid, _Meta} -> Pid;
        undefined    -> undefined
    end.

%% -------------------------------------------------------------------------
%% Back-compat aliases — delegates to with_entity(udr_session, …)
%% -------------------------------------------------------------------------

-doc "Run Fun while holding the cluster-wide lock for IMSI (default 5 s acquire timeout).\n"
     "Back-compat alias for `with_entity(udr_session, Imsi, Fun)`.".
-spec with_session(binary(), fun(() -> Result)) -> Result | {error, session_busy}.
with_session(Imsi, Fun) ->
    with_entity(?SCOPE, Imsi, Fun).

-doc "Run Fun while holding the cluster-wide lock for IMSI, waiting up to TimeoutMs to\n"
     "acquire it. Back-compat alias for `with_entity(udr_session, Imsi, Fun, TimeoutMs)`.".
-spec with_session(binary(), fun(() -> Result), non_neg_integer()) ->
    Result | {error, session_busy}.
with_session(Imsi, Fun, TimeoutMs) ->
    with_entity(?SCOPE, Imsi, Fun, TimeoutMs).

-doc "Pid currently holding the session lock for IMSI, or undefined.\n"
     "Back-compat alias for `whereis_entity(udr_session, Imsi)`.".
-spec whereis_session(binary()) -> pid() | undefined.
whereis_session(Imsi) ->
    whereis_entity(?SCOPE, Imsi).

%% -------------------------------------------------------------------------
%% Internal helpers
%% -------------------------------------------------------------------------

%% Try to register self() as the (Scope, Key) holder, polling until the deadline.
-spec acquire(atom(), binary(), integer()) -> ok | {error, session_busy}.
acquire(Scope, Key, Deadline) ->
    case syn:register(Scope, Key, self()) of
        ok ->
            ok;
        {error, taken} ->
            Now = erlang:monotonic_time(millisecond),
            case Now >= Deadline of
                true ->
                    {error, session_busy};
                false ->
                    timer:sleep(min(?RETRY_INTERVAL, Deadline - Now)),
                    acquire(Scope, Key, Deadline)
            end
    end.
