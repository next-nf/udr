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
-module(udr_hss_dsd_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([dsd_registered_returns_effect/1,
         dsd_not_registered_returns_error/1,
         dsd_purged_returns_not_registered/1]).

all() ->
    [dsd_registered_returns_effect,
     dsd_not_registered_returns_error,
     dsd_purged_returns_not_registered].

init_per_testcase(_TestCase, Config) ->
    application:set_env(udr_db, backend, udr_db_ets),
    {ok, Started} = application:ensure_all_started(udr_hss),
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    [ application:stop(A) || A <- lists:reverse(?config(started, Config)) ],
    ok.

provision(Imsi) ->
    ok = udr_data:put_subscription_data(
           Imsi, #{<<"apn_config_profile">> => #{<<"context_id">> => 1}}).

register_mme(Imsi, Host) ->
    {ok, _, _} = udr_hss:handle_ulr(#{imsi => Imsi, mme_host => Host,
                                      mme_realm => <<"epc">>, rat_type => eutran,
                                      visited_plmn => <<>>}),
    ok.

dsd_registered_returns_effect(_Config) ->
    Imsi = <<"001010000000501">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    {ok, Effects} = udr_hss:delete_subscriber_data(Imsi, 1),
    ?assertMatch([{delete_subscriber_data,
                   #{imsi := Imsi, mme_host := <<"mme-a">>,
                     mme_realm := <<"epc">>, dsr_flags := 1}}], Effects),
    ok.

dsd_not_registered_returns_error(_Config) ->
    Imsi = <<"001010000000502">>,
    provision(Imsi),
    ?assertEqual({error, not_registered}, udr_hss:delete_subscriber_data(Imsi, 1)),
    ok.

dsd_purged_returns_not_registered(_Config) ->
    Imsi = <<"001010000000503">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    {ok, _, _} = udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-a">>}),
    ?assertEqual({error, not_registered}, udr_hss:delete_subscriber_data(Imsi, 1)),
    ok.
