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
Common Test hook that empties the shared Mnesia store around each suite.

The Mnesia backend uses node-wide named tables; a suite that leaves udr_db
running (its apps not fully stopped) lets records accumulate across the whole
`rebar3 ct` run and contaminate later suites.

This hook fires before and after every suite to:
  1. Clear all non-schema Mnesia tables — removes stale data from a prior suite
     that left the store running.
  2. Recreate udr_data collections when the applications are running but their
     Mnesia tables are absent (i.e. a prior suite called teardown_mnesia while
     udr_db was still up). This prevents the next suite's ensure_all_started/1
     from silently skipping ensure_collections/0.

When Mnesia is not running the hook is a no-op.  Any error in the hook is
swallowed so it can never turn a green suite red.

Registered globally via `{ct_hooks, [udr_preload_cth, udr_db_reset_cth]}` in
rebar.config.
""".
-export([id/1, init/2, pre_init_per_suite/3, post_end_per_suite/4]).

id(_Opts) -> ?MODULE.

init(_Id, _Opts) -> {ok, #{}}.

pre_init_per_suite(_Suite, Config, State) ->
    _ = catch reset_tables(),
    {Config, State}.

post_end_per_suite(_Suite, _Config, Return, State) ->
    _ = catch reset_tables(),
    {Return, State}.

%% Clear all non-schema Mnesia tables and, when udr_data is running but its
%% tables are absent (Mnesia was restarted by a prior suite while the apps
%% stayed up), recreate them so the next suite starts from a consistent state.
reset_tables() ->
    case mnesia:system_info(is_running) of
        yes ->
            Tables = [T || T <- mnesia:system_info(local_tables), T =/= schema],
            [catch mnesia:clear_table(T) || T <- Tables],
            maybe_ensure_collections();
        _ ->
            %% Mnesia is not running; nothing to clear.
            ok
    end.

%% If udr_data is started but none of its collections exist (Mnesia was
%% restarted from scratch while the app stayed up), recreate them now.
%% ensure_collections/0 is idempotent so calling it when tables already exist
%% is harmless.
maybe_ensure_collections() ->
    case lists:keymember(udr_data, 1, application:which_applications()) of
        true  -> catch udr_data:ensure_collections();
        false -> ok
    end.
