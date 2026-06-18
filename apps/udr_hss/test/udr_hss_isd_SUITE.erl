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
-module(udr_hss_isd_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([isd_registered_returns_effect/1,
         isd_not_registered_returns_error/1,
         isd_purged_returns_not_registered/1,
         isd_malformed_registration_returns_not_registered/1]).

all() ->
    [isd_registered_returns_effect,
     isd_not_registered_returns_error,
     isd_purged_returns_not_registered,
     isd_malformed_registration_returns_not_registered].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    Config.

end_per_suite(_Config) ->
    udr_db_ct:teardown_mnesia(),
    ok.

init_per_testcase(_TestCase, Config) ->
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

isd_registered_returns_effect(_Config) ->
    Imsi = <<"001010000000401">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    {ok, Effects} = udr_hss:insert_subscriber_data(Imsi),
    ?assertMatch([{insert_subscriber_data,
                   #{imsi := Imsi, mme_host := <<"mme-a">>,
                     mme_realm := <<"epc">>, subscription_data := #{}}}], Effects),
    ok.

isd_not_registered_returns_error(_Config) ->
    Imsi = <<"001010000000402">>,
    provision(Imsi),
    ?assertEqual({error, not_registered}, udr_hss:insert_subscriber_data(Imsi)),
    ok.

isd_purged_returns_not_registered(_Config) ->
    Imsi = <<"001010000000403">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    {ok, _, _} = udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-a">>}),
    ?assertEqual({error, not_registered}, udr_hss:insert_subscriber_data(Imsi)),
    ok.

%% A registration document missing its serving-node identity must not crash the
%% handler (function_clause inside the per-IMSI lock) — it is treated as inactive.
isd_malformed_registration_returns_not_registered(_Config) ->
    Imsi = <<"001010000000404">>,
    provision(Imsi),
    ok = udr_data:put_3gpp_access_registration(Imsi, #{<<"status">> => <<"registered">>}),
    ?assertEqual({error, not_registered}, udr_hss:insert_subscriber_data(Imsi)),
    ok.
