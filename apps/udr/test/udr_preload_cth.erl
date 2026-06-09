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

-module(udr_preload_cth).
-moduledoc """
Common Test hook that eagerly loads the code of every running application.

Erlang loads a module's `.beam` lazily, on the first call into it. On a fresh CI
runner that first call also pays the file read off a cold disk, and those load
latencies surface inside test cases as sporadic slowness or, worse, as timetrap
flakiness that never reproduces locally (where the beams are already in the file
cache).

This hook removes that variable: after each suite's `init_per_suite` has started
its applications, it walks `application:which_applications/0`, collects every
module each running app owns, and forces it resident with `code:ensure_loaded/1`.
It is registered globally via `{ct_hooks, ...}` in `rebar.config`, so it applies
to the whole `rebar3 ct` run with no per-suite wiring. Loading is idempotent and
cheap once a module is resident, so re-running it after every suite is harmless.

It only ever loads code and never mutates the suite's result: any error while
preloading is swallowed so a code-path quirk can never turn a green suite red.
""".

%% CT hook callbacks
-export([id/1, init/2, post_init_per_suite/4]).

%% A single shared instance regardless of how many times it is listed.
id(_Opts) -> ?MODULE.

init(_Id, _Opts) -> {ok, #{}}.

%% Runs right after a suite's init_per_suite, i.e. right after that suite has
%% started its applications. Preload, then hand the suite's Config back untouched.
post_init_per_suite(_Suite, _Config, Return, State) ->
    _ = preload_running_apps(),
    {Return, State}.

%% Force-load every module owned by a currently-running application. Returns the
%% number of modules considered; purely informational.
preload_running_apps() ->
    try
        Mods = lists:append([app_modules(App)
                             || {App, _Desc, _Vsn} <- application:which_applications()]),
        lists:foreach(fun(M) -> _ = code:ensure_loaded(M) end, Mods),
        length(Mods)
    catch
        _:_ -> 0
    end.

app_modules(App) ->
    case application:get_key(App, modules) of
        {ok, Mods} -> Mods;
        undefined  -> []
    end.
