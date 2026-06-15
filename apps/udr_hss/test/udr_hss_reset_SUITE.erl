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
    %% Reset is a global procedure (it enumerates ALL registrations). Clear this
    %% suite's IMSIs up front so cases do not leak registrations into one another
    %% when udr_db stays running across cases within the wider test run.
    [ udr_data:delete_3gpp_access_registration(I) || I <- imsis() ],
    [{started, Started} | Config].

end_per_testcase(_TestCase, Config) ->
    [ application:stop(A) || A <- lists:reverse(?config(started, Config)) ],
    ok.

%% Every IMSI this suite registers; cleared at init so cases stay independent.
imsis() ->
    [<<"001010000000601">>, <<"001010000000602">>, <<"001010000000603">>,
     <<"001010000000604">>, <<"001010000000605">>].

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

%% reset/0 is a global enumeration, so these cases use suite-unique serving-node
%% hosts and assert membership/exclusion rather than a global exact match — that
%% keeps them robust to registrations other suites leave in the shared store.
reset_fans_out_to_distinct_nodes(_Config) ->
    provision(<<"001010000000601">>), register_mme(<<"001010000000601">>, <<"reset-mme-x">>),
    provision(<<"001010000000602">>), register_mme(<<"001010000000602">>, <<"reset-mme-y">>),
    {ok, Effects} = udr_hss:reset(),
    H = hosts(Effects),
    ?assert(lists:member(<<"reset-mme-x">>, H)),
    ?assert(lists:member(<<"reset-mme-y">>, H)),
    ok.

reset_dedups_same_node(_Config) ->
    provision(<<"001010000000603">>), register_mme(<<"001010000000603">>, <<"reset-mme-z">>),
    provision(<<"001010000000604">>), register_mme(<<"001010000000604">>, <<"reset-mme-z">>),
    {ok, Effects} = udr_hss:reset(),
    ?assertEqual(1, length([X || X <- hosts(Effects), X =:= <<"reset-mme-z">>])),
    ok.

reset_excludes_purged(_Config) ->
    provision(<<"001010000000605">>), register_mme(<<"001010000000605">>, <<"reset-mme-w">>),
    {ok, _, _} = udr_hss:handle_pur(#{imsi => <<"001010000000605">>, mme_host => <<"reset-mme-w">>}),
    {ok, Effects} = udr_hss:reset(),
    ?assertNot(lists:member(<<"reset-mme-w">>, hosts(Effects))),
    ok.
