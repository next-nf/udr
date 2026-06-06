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
-moduledoc "Cluster-wide per-IMSI session lock over `syn`. `with_session/2,3` gives a\n"
           "subscriber a single owner across the cluster for the duration of a request;\n"
           "the lock auto-releases on completion, crash, or node-down.".

-export([scope/0, with_session/2, with_session/3, whereis_session/1]).

-define(SCOPE, udr_session).
-define(DEFAULT_TIMEOUT, 5000).
-define(RETRY_INTERVAL, 25).

-doc "The `syn` scope used for per-IMSI session locks.".
-spec scope() -> atom().
scope() ->
    ?SCOPE.

-doc "Run Fun while holding the cluster-wide lock for IMSI (default 5s acquire timeout).".
-spec with_session(binary(), fun(() -> Result)) -> Result | {error, session_busy}.
with_session(Imsi, Fun) ->
    with_session(Imsi, Fun, ?DEFAULT_TIMEOUT).

-doc "Run Fun while holding the cluster-wide lock for IMSI, waiting up to TimeoutMs to\n"
     "acquire it (queue-then-proceed). Returns Fun's result, or {error, session_busy} on\n"
     "timeout. The lock is released when Fun returns or raises, and automatically if this\n"
     "process or its node dies. NOTE: Fun should not itself return {error, session_busy}.\n"
     "NOT re-entrant: Fun must not call with_session/2,3 again for the SAME IMSI in the\n"
     "same process — syn would re-register the same pid and the inner release would drop\n"
     "the outer lock. (S6a procedures never nest on one IMSI, so this does not arise here.)".
-spec with_session(binary(), fun(() -> Result), non_neg_integer()) ->
    Result | {error, session_busy}.
with_session(Imsi, Fun, TimeoutMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    case acquire(Imsi, Deadline) of
        ok ->
            try Fun()
            after _ = syn:unregister(?SCOPE, Imsi)
            end;
        {error, session_busy} = E ->
            E
    end.

-doc "Pid currently holding the session lock for IMSI, or undefined.".
-spec whereis_session(binary()) -> pid() | undefined.
whereis_session(Imsi) ->
    case syn:lookup(?SCOPE, Imsi) of
        {Pid, _Meta} -> Pid;
        undefined    -> undefined
    end.

%% Try to register self() as the IMSI's holder, polling until the deadline.
-spec acquire(binary(), integer()) -> ok | {error, session_busy}.
acquire(Imsi, Deadline) ->
    case syn:register(?SCOPE, Imsi, self()) of
        ok ->
            ok;
        {error, taken} ->
            Now = erlang:monotonic_time(millisecond),
            case Now >= Deadline of
                true ->
                    {error, session_busy};
                false ->
                    timer:sleep(min(?RETRY_INTERVAL, Deadline - Now)),
                    acquire(Imsi, Deadline)
            end
    end.
