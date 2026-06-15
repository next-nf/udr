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

-module(udr_db_reset_cth).
-moduledoc """
Common Test hook that empties the shared udr_db store around each suite.

The ets backend uses one node-wide named table; a suite that leaves udr_db
running (its apps not fully stopped) lets records accumulate across the whole
`rebar3 ct` run and contaminate later suites. This hook calls udr_db:flush/0
before and after every suite WHEN udr_db is running -- i.e. exactly when a
prior suite leaked it -- so each suite starts from an empty store regardless of
run order. When udr_db is down (its ets table already gone) the hook is a no-op.

Registered globally via {ct_hooks, ...} in rebar.config; flush is gated by the
{udr_db, allow_flush} env, set true only in config/ct.sys.config. Any error is
swallowed so the hook can never turn a green suite red.
""".
-export([id/1, init/2, pre_init_per_suite/3, post_end_per_suite/4]).

id(_Opts) -> ?MODULE.

init(_Id, _Opts) -> {ok, #{}}.

pre_init_per_suite(_Suite, Config, State) ->
    _ = maybe_flush(),
    {Config, State}.

post_end_per_suite(_Suite, _Config, Return, State) ->
    _ = maybe_flush(),
    {Return, State}.

%% Flush only when udr_db is running (leaked from a prior suite or active);
%% otherwise the store is already gone. Backend-agnostic via udr_db:flush/0.
maybe_flush() ->
    case lists:keymember(udr_db, 1, application:which_applications()) of
        true  -> catch udr_db:flush();
        false -> ok
    end,
    ok.
