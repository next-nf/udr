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
-module(udr_hss_reset_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([reset_fans_out_to_distinct_nodes/1,
         reset_dedups_same_node/1,
         reset_excludes_purged/1]).

all() ->
    [reset_fans_out_to_distinct_nodes,
     reset_dedups_same_node,
     reset_excludes_purged].

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

hosts(Effects) ->
    lists:sort([H || {reset, #{mme_host := H}} <- Effects]).

reset_fans_out_to_distinct_nodes(_Config) ->
    provision(<<"001010000000601">>), register_mme(<<"001010000000601">>, <<"mme-a">>),
    provision(<<"001010000000602">>), register_mme(<<"001010000000602">>, <<"mme-b">>),
    {ok, Effects} = udr_hss:reset(),
    ?assertEqual([<<"mme-a">>, <<"mme-b">>], hosts(Effects)),
    ok.

reset_dedups_same_node(_Config) ->
    provision(<<"001010000000603">>), register_mme(<<"001010000000603">>, <<"mme-a">>),
    provision(<<"001010000000604">>), register_mme(<<"001010000000604">>, <<"mme-a">>),
    {ok, Effects} = udr_hss:reset(),
    ?assertEqual([<<"mme-a">>], hosts(Effects)),
    ok.

reset_excludes_purged(_Config) ->
    provision(<<"001010000000605">>), register_mme(<<"001010000000605">>, <<"mme-a">>),
    {ok, _, _} = udr_hss:handle_pur(#{imsi => <<"001010000000605">>, mme_host => <<"mme-a">>}),
    {ok, Effects} = udr_hss:reset(),
    ?assertEqual([], hosts(Effects)),
    ok.
