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

-export([handle_air/1, handle_ulr/1, handle_pur/1]).

-type request() :: #{atom() => term()}.
-type answer() :: #{atom() => term()}.
-type effect() :: {cancel_location, map()}.
-type error_code() :: user_unknown | unable_to_comply | session_busy.

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
            Effects = clr_effect_if_moved(Imsi, NewHost),
            Reg = #{<<"serving_mme_host">>  => NewHost,
                    <<"serving_mme_realm">> => NewRealm,
                    <<"status">>            => <<"registered">>,
                    <<"rat_type">>          => maps:get(rat_type, Req, undefined),
                    <<"visited_plmn">>      => maps:get(visited_plmn, Req, <<>>),
                    <<"updated_at">>        => erlang:system_time(second)},
            ok = udr_data:put_3gpp_access_registration(Imsi, Reg),
            {ok, #{subscription_data => Profile}, Effects}
    end.

clr_effect_if_moved(Imsi, NewHost) ->
    case udr_data:get_3gpp_access_registration(Imsi) of
        {ok, #{<<"serving_mme_host">> := OldHost} = Old} when OldHost =/= NewHost ->
            [{cancel_location, #{imsi => Imsi, mme_host => OldHost,
                                 mme_realm => maps:get(<<"serving_mme_realm">>, Old, <<>>)}}];
        _ ->
            []
    end.

-doc "Handle a Purge-UE request: clear the serving-MME registration. Returns user_unknown\n"
     "for an unprovisioned subscriber (TS 29.272 §7.3.3).".
-spec handle_pur(request()) -> {ok, answer(), [effect()]} | {error, error_code()}.
handle_pur(#{imsi := Imsi}) ->
    in_session(Imsi, fun() -> do_pur(Imsi) end).

do_pur(Imsi) ->
    case udr_data:get_subscription_data(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, _Profile} ->
            ok = udr_data:delete_3gpp_access_registration(Imsi),
            {ok, #{}, []}
    end.

%% --- procedure logic (runs while holding the lock) ---
do_air(#{imsi := Imsi, visited_plmn := SnId, num_vectors := N} = Req) ->
    case udr_data:get_authentication_subscription(Imsi) of
        {error, not_found} ->
            {error, user_unknown};
        {ok, Auth} ->
            #{<<"algorithm">> := AlgoBin, <<"ki">> := K,
              <<"opc">> := OPc, <<"amf">> := AMF} = Auth,
            Algo = algo(AlgoBin),
            case maybe_resync(Imsi, Req, Algo, K, OPc) of
                ok ->
                    case udr_data:advance_sqn(Imsi, N) of
                        {ok, Start} ->
                            {Vectors, _Next} =
                                udr_crypto:generate_eps_vectors(Algo, K, OPc, AMF, Start, N, SnId),
                            {ok, #{vectors => [av_to_map(V) || V <- Vectors]}, []};
                        {error, not_found}     -> {error, user_unknown};
                        {error, cas_exhausted} -> {error, unable_to_comply}
                    end;
                {error, _} = ResyncErr ->
                    ResyncErr
            end
    end.

%% AUTS resync: verify, then repair stored SQN to SQN_MS + 1 (next to allocate).
maybe_resync(Imsi, #{resync := {Rand, Auts}}, Algo, K, OPc) ->
    case udr_crypto:verify_resync(Algo, K, OPc, Rand, Auts) of
        {ok, SqnMs} ->
            <<SqnMsInt:48>> = SqnMs,
            case udr_data:repair_sqn(Imsi, SqnMsInt + 1) of
                ok         -> ok;
                {error, _} -> {error, unable_to_comply}
            end;
        {error, mac_failure} ->
            ok  %% ignore a failed resync; fresh vectors let the UE resync again
    end;
maybe_resync(_Imsi, _Req, _Algo, _K, _OPc) ->
    ok.

%% --- helpers ---
in_session(Imsi, Fun) ->
    udr_cluster:with_session(Imsi, Fun).

algo(<<"milenage">>) -> milenage.

av_to_map(V) ->
    #{rand  => V#eps_av.rand,
      xres  => V#eps_av.xres,
      autn  => V#eps_av.autn,
      kasme => V#eps_av.kasme}.
