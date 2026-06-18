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
-module(udr_data_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).
-export([put_then_get/1, get_unknown_imsi/1,
         advance_sqn_reserves_block/1, advance_sqn_unknown_imsi/1,
         repair_sqn_sets_stored/1, repair_sqn_unknown_imsi/1, concurrent_advance_sqn/1,
         get_am_subscription/1, get_sm_subscription/1, get_am_subscription_unknown_imsi/1,
         registration_put_then_get/1, registration_delete/1,
         get_subscription_data/1, get_subscription_data_unknown_imsi/1,
         delete_authentication_subscription/1, delete_subscription_data/1,
         put_propagates_storage_error/1]).

all() ->
    [put_then_get, get_unknown_imsi,
     advance_sqn_reserves_block, advance_sqn_unknown_imsi,
     repair_sqn_sets_stored, repair_sqn_unknown_imsi, concurrent_advance_sqn,
     get_am_subscription, get_sm_subscription, get_am_subscription_unknown_imsi,
     registration_put_then_get, registration_delete,
     get_subscription_data, get_subscription_data_unknown_imsi,
     delete_authentication_subscription, delete_subscription_data,
     put_propagates_storage_error].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    {ok, _Pid} = udr_db_mnesia:start_link(#{}),
    ok = udr_data:ensure_collections(),
    Config.

end_per_suite(_Config) ->
    catch gen_server:stop(udr_db_mnesia),
    udr_db_ct:teardown_mnesia(),
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Clear collections between test cases.
    mnesia:clear_table(auth_subscription),
    mnesia:clear_table(subscription_data),
    mnesia:clear_table(access_registration),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% auth_subscription

put_then_get(_Config) ->
    Sub = #{<<"ki">> => <<"k">>, <<"opc">> => <<"o">>,
            <<"algorithm">> => <<"milenage">>, <<"amf">> => <<"a">>, <<"sqn">> => 0},
    ok = udr_data:put_authentication_subscription(<<"imsi1">>, Sub),
    {ok, Got} = udr_data:get_authentication_subscription(<<"imsi1">>),
    ?assertEqual(<<"k">>, maps:get(<<"ki">>, Got)),
    ?assertEqual(<<"milenage">>, maps:get(<<"algorithm">>, Got)),
    %% version is metadata — never in the returned doc
    ?assertEqual(error, maps:find(<<"version">>, Got)),
    ok.

get_unknown_imsi(_Config) ->
    ?assertEqual({error, not_found},
                 udr_data:get_authentication_subscription(<<"nope">>)),
    ok.

%% advance_sqn

advance_sqn_reserves_block(_Config) ->
    ok = udr_data:put_authentication_subscription(<<"i">>, #{<<"sqn">> => 1000}),
    ?assertEqual({ok, 1000}, udr_data:advance_sqn(<<"i">>, 3)),
    ?assertEqual({ok, 1003}, udr_data:advance_sqn(<<"i">>, 1)),
    {ok, Sub} = udr_data:get_authentication_subscription(<<"i">>),
    ?assertEqual(1004, maps:get(<<"sqn">>, Sub)),
    ok.

advance_sqn_unknown_imsi(_Config) ->
    ?assertEqual({error, not_found}, udr_data:advance_sqn(<<"nope">>, 1)),
    ok.

repair_sqn_sets_stored(_Config) ->
    ok = udr_data:put_authentication_subscription(<<"i">>, #{<<"sqn">> => 1000}),
    ok = udr_data:repair_sqn(<<"i">>, 5000),
    {ok, Sub} = udr_data:get_authentication_subscription(<<"i">>),
    ?assertEqual(5000, maps:get(<<"sqn">>, Sub)),
    ok.

repair_sqn_unknown_imsi(_Config) ->
    ?assertEqual({error, not_found}, udr_data:repair_sqn(<<"nope">>, 1)),
    ok.

concurrent_advance_sqn(_Config) ->
    ok = udr_data:put_authentication_subscription(<<"i">>, #{<<"sqn">> => 0}),
    NProcs = 8, PerProc = 25, Total = NProcs * PerProc,
    Parent = self(),
    Pids = [ spawn_link(fun() ->
                 Starts = [ begin {ok, S} = udr_data:advance_sqn(<<"i">>, 1), S end
                            || _ <- lists:seq(1, PerProc) ],
                 Parent ! {self(), Starts}
             end) || _ <- lists:seq(1, NProcs) ],
    AllStarts = lists:append([ receive {P, Ss} -> Ss end || P <- Pids ]),
    ?assertEqual(Total, length(AllStarts)),
    ?assertEqual(lists:seq(0, Total - 1), lists:sort(AllStarts)),
    {ok, Sub} = udr_data:get_authentication_subscription(<<"i">>),
    ?assertEqual(Total, maps:get(<<"sqn">>, Sub)),
    ok.

%% subscription_data

get_am_subscription(_Config) ->
    Profile = #{<<"msisdn">> => <<"49100">>, <<"subscriber_status">> => <<"SERVICE_GRANTED">>,
                <<"ambr">> => #{<<"ul">> => 1000, <<"dl">> => 2000},
                <<"apn_config_profile">> => #{<<"context_id">> => 1}},
    ok = udr_data:put_subscription_data(<<"i">>, Profile),
    {ok, Am} = udr_data:get_am_subscription(<<"i">>),
    ?assertEqual(<<"49100">>, maps:get(<<"msisdn">>, Am)),
    ?assertEqual(#{<<"ul">> => 1000, <<"dl">> => 2000}, maps:get(<<"ambr">>, Am)),
    ?assertEqual(error, maps:find(<<"apn_config_profile">>, Am)),
    ?assertEqual(error, maps:find(<<"version">>, Am)),
    ok.

get_sm_subscription(_Config) ->
    Profile = #{<<"msisdn">> => <<"49100">>,
                <<"apn_config_profile">> => #{<<"context_id">> => 1}},
    ok = udr_data:put_subscription_data(<<"i">>, Profile),
    {ok, Sm} = udr_data:get_sm_subscription(<<"i">>),
    ?assertEqual(#{<<"context_id">> => 1}, maps:get(<<"apn_config_profile">>, Sm)),
    ?assertEqual(error, maps:find(<<"msisdn">>, Sm)),
    ok.

get_am_subscription_unknown_imsi(_Config) ->
    ?assertEqual({error, not_found}, udr_data:get_am_subscription(<<"nope">>)),
    ok.

%% registration

registration_put_then_get(_Config) ->
    ?assertEqual({error, not_registered}, udr_data:get_3gpp_access_registration(<<"i">>)),
    Reg = #{<<"serving_mme_host">> => <<"mme1">>, <<"serving_mme_realm">> => <<"epc">>,
            <<"status">> => <<"registered">>},
    ok = udr_data:put_3gpp_access_registration(<<"i">>, Reg),
    {ok, Got} = udr_data:get_3gpp_access_registration(<<"i">>),
    ?assertEqual(<<"mme1">>, maps:get(<<"serving_mme_host">>, Got)),
    ?assertEqual(error, maps:find(<<"version">>, Got)),
    ok.

registration_delete(_Config) ->
    ok = udr_data:put_3gpp_access_registration(<<"i">>, #{<<"serving_mme_host">> => <<"m">>}),
    ok = udr_data:delete_3gpp_access_registration(<<"i">>),
    ?assertEqual({error, not_registered}, udr_data:get_3gpp_access_registration(<<"i">>)),
    ok.

%% get_subscription_data

get_subscription_data(_Config) ->
    Profile = #{<<"msisdn">> => <<"49100">>,
                <<"ambr">> => #{<<"ul">> => 1, <<"dl">> => 2},
                <<"apn_config_profile">> => #{<<"context_id">> => 1}},
    ok = udr_data:put_subscription_data(<<"i">>, Profile),
    {ok, Got} = udr_data:get_subscription_data(<<"i">>),
    ?assertEqual(<<"49100">>, maps:get(<<"msisdn">>, Got)),
    ?assertEqual(#{<<"context_id">> => 1}, maps:get(<<"apn_config_profile">>, Got)),
    ?assertEqual(error, maps:find(<<"version">>, Got)),
    ok.

get_subscription_data_unknown_imsi(_Config) ->
    ?assertEqual({error, not_found}, udr_data:get_subscription_data(<<"nope">>)),
    ok.

%% delete_subscriber_data

delete_authentication_subscription(_Config) ->
    ok = udr_data:put_authentication_subscription(<<"i">>, #{<<"ki">> => <<"k">>}),
    ok = udr_data:delete_authentication_subscription(<<"i">>),
    ?assertEqual({error, not_found}, udr_data:get_authentication_subscription(<<"i">>)),
    ok.

delete_subscription_data(_Config) ->
    ok = udr_data:put_subscription_data(<<"i">>, #{<<"msisdn">> => <<"49">>}),
    ok = udr_data:delete_subscription_data(<<"i">>),
    ?assertEqual({error, not_found}, udr_data:get_subscription_data(<<"i">>)),
    ok.

%% A backend write failure must PROPAGATE through the put_* seam as {error, _},
%% never collapse into a crash (the bug a {ok,_V}=put(...) match introduced — a
%% storage failure then surfaced to the caller as a 4xx instead of a 5xx).
put_propagates_storage_error(_Config) ->
    Restore = persistent_term:get({udr_db, backend}, udr_db_mnesia),
    persistent_term:put({udr_db, backend}, udr_db_failing_backend),
    try
        ?assertEqual({error, storage_unavailable},
                     udr_data:put_authentication_subscription(<<"i">>, #{<<"ki">> => <<"k">>})),
        ?assertEqual({error, storage_unavailable},
                     udr_data:put_subscription_data(<<"i">>, #{<<"msisdn">> => <<"49">>})),
        ?assertEqual({error, storage_unavailable},
                     udr_data:put_3gpp_access_registration(<<"i">>, #{<<"status">> => <<"r">>}))
    after
        persistent_term:put({udr_db, backend}, Restore)
    end,
    ok.
