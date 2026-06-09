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
-module(udr_hss).
-moduledoc "S6a HSS application logic. Protocol-agnostic handlers operate on semantic\n"
           "maps and run inside the per-IMSI cluster lock; CLR is emitted as an effect for\n"
           "the transport (udr_diameter) to execute.".
-import_record(udr_crypto, [eps_av]).

-export([handle_air/1, handle_ulr/1, handle_pur/1, handle_nor/1, insert_subscriber_data/1, delete_subscriber_data/2, reset/0]).

-type request() :: #{atom() => term()}.
-type answer() :: #{atom() => term()}.
-type effect() :: {cancel_location, map()} | {insert_subscriber_data, map()} | {delete_subscriber_data, map()} | {reset, map()}.
-type error_code() :: user_unknown | unable_to_comply | session_busy | unknown_serving_node | authentication_data_unavailable.

-doc "Handle an Authentication-Information request: return N EPS vectors (and apply an\n"
     "AUTS resync if present), advancing the stored SQN. Runs under the per-IMSI lock.\n"
     " Request keys: imsi, visited_plmn (3-byte SN-id), num_vectors, and optional resync => {Rand, Auts}.".
-spec handle_air(request()) ->
    {ok, answer(), [effect()]} | {error, error_code()}.
handle_air(#{imsi := Imsi} = Req) ->
    in_session(Imsi, fun() -> do_air(Req) end).

-doc "Handle an Update-Location request: return the subscription profile, (re)register\n"
     "the serving MME, and emit a cancel_location effect if a different MME was registered.\n"
     "Request keys: imsi, mme_host, mme_realm, rat_type, visited_plmn.".
-spec handle_ulr(request()) -> {ok, answer(), [effect()]} | {error, error_code()}.
handle_ulr(#{imsi := Imsi} = Req) ->
    in_session(Imsi, fun() -> do_ulr(Req) end).

do_ulr(#{imsi := Imsi, mme_host := NewHost, mme_realm := NewRealm} = Req) ->
    case udr_data:get_subscription_data(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, Profile} ->
            CancelType = case maps:get(initial_attach, Req, false) of
                             true  -> initial_attach_procedure;
                             false -> mme_update_procedure
                         end,
            Effects = clr_effect_if_moved(Imsi, NewHost, CancelType),
            Reg = #{<<"serving_mme_host">>  => NewHost,
                    <<"serving_mme_realm">> => NewRealm,
                    <<"status">>            => <<"registered">>,
                    <<"rat_type">>          => maps:get(rat_type, Req, undefined),
                    <<"visited_plmn">>      => maps:get(visited_plmn, Req, <<>>),
                    <<"updated_at">>        => erlang:system_time(second)},
            ok = udr_data:put_3gpp_access_registration(Imsi, Reg),
            Answer = case maps:get(skip_subscriber_data, Req, false) of
                         true  -> #{};
                         false -> #{subscription_data => Profile}
                     end,
            {ok, Answer, Effects}
    end.

-doc "Decide an HSS-initiated Reset fan-out: one reset effect per distinct, non-purged\n"
     "registered serving node, telling each to mark its subscribers as needing restoration.".
-spec reset() -> {ok, [effect()]} | {error, term()}.
reset() ->
    case udr_data:registered_serving_nodes() of
        {ok, Nodes} ->
            {ok, [{reset, #{mme_host => H, mme_realm => R}} || {H, R} <- Nodes]};
        {error, _} = E ->
            E
    end.

-doc "Decide an HSS-initiated Insert Subscriber Data push: if the subscriber is registered\n"
     "(and not purged), return an insert_subscriber_data effect carrying the current\n"
     "Subscription-Data for the serving MME; otherwise {error, not_registered}.".
-spec insert_subscriber_data(binary()) -> {ok, [effect()]} | {error, not_registered | not_found}.
insert_subscriber_data(Imsi) ->
    in_session(Imsi, fun() -> do_isd(Imsi) end).

do_isd(Imsi) ->
    case udr_data:get_3gpp_access_registration(Imsi) of
        {ok, #{<<"ue_purged">> := true}} ->
            {error, not_registered};
        {ok, #{<<"serving_mme_host">> := Host} = Reg} ->
            case udr_data:get_subscription_data(Imsi) of
                {ok, Profile} ->
                    {ok, [{insert_subscriber_data,
                           #{imsi      => Imsi,
                             mme_host  => Host,
                             mme_realm => maps:get(<<"serving_mme_realm">>, Reg, <<>>),
                             subscription_data => Profile}}]};
                {error, not_found} ->
                    {error, not_found}
            end;
        {error, not_registered} ->
            {error, not_registered}
    end.

-doc "Decide an HSS-initiated Delete Subscriber Data withdrawal: if the subscriber is\n"
     "registered (and not purged), return a delete_subscriber_data effect carrying the\n"
     "DSR-Flags bitmask of data classes to withdraw; otherwise {error, not_registered}.".
-spec delete_subscriber_data(binary(), non_neg_integer()) ->
    {ok, [effect()]} | {error, not_registered}.
delete_subscriber_data(Imsi, Flags) ->
    in_session(Imsi, fun() -> do_dsd(Imsi, Flags) end).

do_dsd(Imsi, Flags) ->
    case udr_data:get_3gpp_access_registration(Imsi) of
        {ok, #{<<"ue_purged">> := true}} ->
            {error, not_registered};
        {ok, #{<<"serving_mme_host">> := Host} = Reg} ->
            {ok, [{delete_subscriber_data,
                   #{imsi      => Imsi,
                     mme_host  => Host,
                     mme_realm => maps:get(<<"serving_mme_realm">>, Reg, <<>>),
                     dsr_flags => Flags}}]};
        {error, not_registered} ->
            {error, not_registered}
    end.

clr_effect_if_moved(Imsi, NewHost, CancelType) ->
    case udr_data:get_3gpp_access_registration(Imsi) of
        {ok, #{<<"serving_mme_host">> := OldHost} = Old} when OldHost =/= NewHost ->
            case maps:get(<<"ue_purged">>, Old, false) of
                true ->
                    [];   %% the purged node already dropped the UE; suppress Cancel Location
                false ->
                    [{cancel_location, #{imsi => Imsi, mme_host => OldHost,
                                         mme_realm => maps:get(<<"serving_mme_realm">>, Old, <<>>),
                                         cancellation_type => CancelType}}]
            end;
        _ ->
            []
    end.

-doc "Handle a Purge-UE request: if the purging node is the registered serving MME, mark\n"
     "the subscriber UE-purged and freeze the M-TMSI; otherwise succeed without freezing.\n"
     "Returns user_unknown for an unprovisioned subscriber. Request keys: imsi, mme_host.".
-spec handle_pur(request()) -> {ok, answer(), [effect()]} | {error, error_code()}.
handle_pur(#{imsi := Imsi} = Req) ->
    in_session(Imsi, fun() -> do_pur(Req) end).

do_pur(#{imsi := Imsi} = Req) ->
    Origin = maps:get(mme_host, Req, undefined),
    case udr_data:get_subscription_data(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, _Profile} ->
            case udr_data:get_3gpp_access_registration(Imsi) of
                {ok, #{<<"serving_mme_host">> := Origin} = Reg} when Origin =/= undefined ->
                    %% Purge from the registered serving MME: mark purged, freeze M-TMSI.
                    ok = udr_data:put_3gpp_access_registration(
                           Imsi, Reg#{<<"ue_purged">> => true}),
                    {ok, #{freeze_m_tmsi => true}, []};
                _ ->
                    %% Unknown serving node (no registration, or a different MME): no freeze.
                    {ok, #{freeze_m_tmsi => false}, []}
            end
    end.

-doc "Handle a Notify request: if the notifying node is the registered serving MME, store\n"
     "the notified Terminal-Information and succeed; otherwise return unknown_serving_node.\n"
     "Returns user_unknown for an unprovisioned subscriber. Request keys: imsi, mme_host,\n"
     "and optional terminal_information.".
-spec handle_nor(request()) -> {ok, answer(), [effect()]} | {error, error_code()}.
handle_nor(#{imsi := Imsi} = Req) ->
    in_session(Imsi, fun() -> do_nor(Req) end).

do_nor(#{imsi := Imsi} = Req) ->
    Origin = maps:get(mme_host, Req, undefined),
    case udr_data:get_subscription_data(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, _Profile} ->
            case udr_data:get_3gpp_access_registration(Imsi) of
                {ok, #{<<"serving_mme_host">> := Origin} = Reg} when Origin =/= undefined ->
                    Reg1 = case maps:get(terminal_information, Req, undefined) of
                               undefined -> Reg;
                               TI        -> Reg#{<<"terminal_information">> => TI}
                           end,
                    ok = udr_data:put_3gpp_access_registration(Imsi, Reg1),
                    {ok, #{}, []};
                _ ->
                    {error, unknown_serving_node}
            end
    end.

%% --- procedure logic (runs while holding the lock) ---
do_air(#{imsi := Imsi, visited_plmn := SnId, num_vectors := N} = Req) ->
    case udr_data:get_authentication_subscription(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, Auth} ->
            case auth_material(Auth) of
                {error, invalid} ->
                    {error, authentication_data_unavailable};
                {ok, Algo, K, OPc, AMF} ->
                    case maybe_resync(Imsi, Req, Algo, K, OPc) of
                        ok ->
                            case udr_data:advance_sqn(Imsi, N) of
                                {ok, Start} ->
                                    {Vectors, _Next} =
                                        udr_crypto:generate_eps_vectors(Algo, K, OPc, AMF, Start, N, SnId),
                                    {ok, #{vectors => [av_to_map(V) || V <- Vectors]}, []};
                                {error, not_found}     -> {error, user_unknown};
                                {error, cas_exhausted} -> {error, authentication_data_unavailable}
                            end;
                        {error, _} = ResyncErr ->
                            ResyncErr
                    end
            end
    end.

%% Validate the stored authentication material; return the algorithm and keys, or
%% {error, invalid} when a required field is missing or the algorithm is unknown
%% (the HSS then answers DIAMETER_ERROR_AUTHENTICATION_DATA_UNAVAILABLE).
auth_material(#{<<"algorithm">> := AlgoBin, <<"ki">> := K,
                <<"opc">> := OPc, <<"amf">> := AMF}) ->
    case algo(AlgoBin) of
        {ok, Algo} -> {ok, Algo, K, OPc, AMF};
        error      -> {error, invalid}
    end;
auth_material(_Incomplete) ->
    {error, invalid}.

%% AUTS resync: verify, then repair stored SQN to SQN_MS + 1 (next to allocate).
maybe_resync(Imsi, #{resync := {Rand, Auts}}, Algo, K, OPc) ->
    case udr_crypto:verify_resync(Algo, K, OPc, Rand, Auts) of
        {ok, SqnMs} ->
            <<SqnMsInt:48>> = SqnMs,
            case udr_data:repair_sqn(Imsi, SqnMsInt + 1) of
                ok         -> ok;
                {error, _} -> {error, authentication_data_unavailable}
            end;
        {error, mac_failure} ->
            ok  %% ignore a failed resync; fresh vectors let the UE resync again
    end;
maybe_resync(_Imsi, _Req, _Algo, _K, _OPc) ->
    ok.

%% --- helpers ---
in_session(Imsi, Fun) ->
    udr_cluster:with_session(Imsi, Fun).

algo(<<"milenage">>) -> {ok, milenage};
algo(_)              -> error.

av_to_map(V) ->
    #{rand  => V#eps_av.rand,
      xres  => V#eps_av.xres,
      autn  => V#eps_av.autn,
      kasme => V#eps_av.kasme}.
