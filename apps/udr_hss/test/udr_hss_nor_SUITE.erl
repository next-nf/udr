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
-module(udr_hss_nor_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([nor_from_registered_mme_stores_terminal_info/1,
         nor_unknown_subscriber_returns_user_unknown/1,
         nor_from_unregistered_node_returns_unknown_serving_node/1,
         nor_from_purged_registration_returns_unknown_serving_node/1]).

all() ->
    [nor_from_registered_mme_stores_terminal_info,
     nor_unknown_subscriber_returns_user_unknown,
     nor_from_unregistered_node_returns_unknown_serving_node,
     nor_from_purged_registration_returns_unknown_serving_node].

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

nor_from_registered_mme_stores_terminal_info(_Config) ->
    Imsi = <<"001010000000301">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    Req = #{imsi => Imsi, mme_host => <<"mme-a">>,
            terminal_information => #{<<"imei">> => <<"3534">>}},
    {ok, #{}, []} = udr_hss:handle_nor(Req),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(#{<<"imei">> => <<"3534">>},
                 maps:get(<<"terminal_information">>, Reg)),
    ok.

nor_unknown_subscriber_returns_user_unknown(_Config) ->
    ?assertEqual({error, user_unknown},
                 udr_hss:handle_nor(#{imsi => <<"nope-nor">>, mme_host => <<"mme-a">>})),
    ok.

nor_from_unregistered_node_returns_unknown_serving_node(_Config) ->
    Imsi = <<"001010000000302">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    ?assertEqual({error, unknown_serving_node},
                 udr_hss:handle_nor(#{imsi => Imsi, mme_host => <<"mme-x">>})),
    ok.

%% Even the registered serving node may not post NOR once the UE is purged: the
%% registration is no longer active, so the HSS answers unknown_serving_node.
nor_from_purged_registration_returns_unknown_serving_node(_Config) ->
    Imsi = <<"001010000000303">>,
    provision(Imsi),
    ok = register_mme(Imsi, <<"mme-a">>),
    {ok, _, _} = udr_hss:handle_pur(#{imsi => Imsi, mme_host => <<"mme-a">>}),
    ?assertEqual({error, unknown_serving_node},
                 udr_hss:handle_nor(#{imsi => Imsi, mme_host => <<"mme-a">>})),
    ok.
