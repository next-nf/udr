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
-module(udr_db_app_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0]).
-export([app_boot/1]).

all() -> [app_boot].

app_boot(_Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    {ok, Started} = application:ensure_all_started(udr_db),
    ok = udr_db:ensure_collection(auth_subscription, #{}),
    try
        {ok, _} = udr_db:put(auth_subscription, <<"boot-imsi">>, #{<<"ki">> => <<"k">>}),
        {ok, Doc, _Vsn} = udr_db:get(auth_subscription, <<"boot-imsi">>),
        ?assertEqual(<<"k">>, maps:get(<<"ki">>, Doc))
    after
        [ application:stop(A) || A <- lists:reverse(Started) ],
        udr_db_ct:teardown_mnesia()
    end,
    ok.
