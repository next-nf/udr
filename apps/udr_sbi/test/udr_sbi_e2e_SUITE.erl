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
-module(udr_sbi_e2e_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([sbi_register_visible_to_data_layer/1]).

-define(PORT, 18081).

all() -> [sbi_register_visible_to_data_layer].

init_per_suite(Config) ->
    application:set_env(udr_db, backend, udr_db_mnesia),
    application:set_env(udr_db, backend_opts, #{storage => ram_copies}),
    ok = udr_db_ct:setup_mnesia_ram(),
    application:load(udr_sbi),
    application:set_env(udr_sbi, port, ?PORT),
    {ok, S1} = application:ensure_all_started(udr_data),
    {ok, S2} = application:ensure_all_started(udr_sbi),
    {ok, _}  = application:ensure_all_started(inets),
    [{started, lists:usort(S1 ++ S2)} | Config].

end_per_suite(Config) ->
    Started = ?config(started, Config),
    [application:stop(A) || A <- lists:reverse(Started)],
    udr_db_ct:teardown_mnesia(),
    ok.

%% a registration PUT via the SBI is what the S6a/data layer reads back
sbi_register_visible_to_data_layer(_Config) ->
    Imsi = <<"001010000000009">>,
    U = "http://127.0.0.1:" ++ integer_to_list(?PORT)
        ++ "/nudr-dr/v1/subscription-data/imsi-" ++ binary_to_list(Imsi)
        ++ "/context-data/amf-3gpp-access",
    Body = iolist_to_binary(json:encode(#{<<"mme_host">> => <<"mme-x">>,
                                          <<"mme_realm">> => <<"epc">>})),
    {ok, {{_, 204, _}, _, _}} =
        httpc:request(put, {U, [], "application/json", Body}, [], [{body_format, binary}]),
    {ok, Reg} = udr_data:get_3gpp_access_registration(Imsi),
    ?assertEqual(<<"mme-x">>, maps:get(<<"mme_host">>, Reg)),
    ok.
