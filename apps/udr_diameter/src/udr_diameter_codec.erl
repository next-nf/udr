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
-module(udr_diameter_codec).
-moduledoc "Translation between S6a map messages ([Name|AvpMap]) and udr_hss semantic\n"
           "maps. Honors OTP map arity: required-once AVPs are bare, optional/repeatable\n"
           "are lists, grouped are nested maps. The single S6a<->semantic conversion point.".

-export([decode_air/1, decode_ulr/1, decode_pur/1,
         encode_air_answer/1, encode_ulr_answer/1, encode_pua_answer/1, clr_request/1]).

-define(SUCCESS, 2001).
-define(UNABLE_TO_COMPLY, 5012).
-define(USER_UNKNOWN, 5001).
-define(UNKNOWN_EPS_SUBSCRIPTION, 5420).
-define(VENDOR_3GPP, 10415).

-doc "Decode an AIR AVP map into the semantic AIR request for udr_hss:handle_air/1.".
-spec decode_air(map()) -> map().
decode_air(#{'User-Name' := Imsi, 'Visited-PLMN-Id' := VPlmn} = Avps) ->
    ReqInfo = first(maps:get('Requested-EUTRAN-Authentication-Info', Avps, [])),
    #{imsi         => Imsi,
      visited_plmn => VPlmn,
      num_vectors  => first_int(maps:get('Number-Of-Requested-Vectors', ReqInfo, []), 1),
      resync       => resync(maps:get('Re-Synchronization-Info', ReqInfo, []))}.

-doc "Decode a ULR AVP map into the semantic ULR request.".
-spec decode_ulr(map()) -> map().
decode_ulr(#{'User-Name' := Imsi, 'Origin-Host' := Host, 'Origin-Realm' := Realm} = Avps) ->
    #{imsi         => Imsi,
      mme_host     => Host,
      mme_realm    => Realm,
      rat_type     => maps:get('RAT-Type', Avps, undefined),
      visited_plmn => maps:get('Visited-PLMN-Id', Avps, <<>>)}.

-doc "Decode a PUR AVP map into the semantic PUR request.".
-spec decode_pur(map()) -> map().
decode_pur(#{'User-Name' := Imsi}) ->
    #{imsi => Imsi}.

-doc "Build the AIA answer AVPs from udr_hss:handle_air/1's result.".
-spec encode_air_answer(term()) -> map().
encode_air_answer({ok, #{vectors := Vs}}) ->
    EVs = [eutran_vector(I, V) || {I, V} <- enumerate(Vs)],
    #{'Result-Code' => [?SUCCESS],
      'Authentication-Info' => [#{'E-UTRAN-Vector' => EVs}]};
encode_air_answer({error, Reason}) ->
    error_avps(Reason).

-doc "Build the ULA answer AVPs (incl. minimal Subscription-Data) from handle_ulr's result.".
-spec encode_ulr_answer(term()) -> map().
encode_ulr_answer({ok, #{subscription_data := Profile}}) ->
    #{'Result-Code' => [?SUCCESS],
      'ULA-Flags' => [1],
      'Subscription-Data' => [subscription_data(Profile)]};
encode_ulr_answer({error, Reason}) ->
    error_avps(Reason).

-doc "Build the PUA answer AVPs from handle_pur's result.".
-spec encode_pua_answer(term()) -> map().
encode_pua_answer({ok, _}) ->
    #{'Result-Code' => [?SUCCESS], 'PUA-Flags' => [1]};
encode_pua_answer({error, Reason}) ->
    error_avps(Reason).

-doc "Build the CLR request AVPs (HSS-originated) for the cancel_location effect.".
-spec clr_request(map()) -> map().
clr_request(#{imsi := Imsi, mme_host := Host, mme_realm := Realm}) ->
    #{'User-Name' => Imsi,
      'Destination-Host'  => Host,
      'Destination-Realm' => Realm,
      'Cancellation-Type' => 2}.   %% 2 = SUBSCRIPTION_WITHDRAWAL

%% --- error mapping: 3GPP vendor codes via Experimental-Result; base codes via Result-Code ---
error_avps(user_unknown) ->
    experimental(?USER_UNKNOWN);
error_avps(unknown_eps_subscription) ->
    experimental(?UNKNOWN_EPS_SUBSCRIPTION);
error_avps(_Other) ->
    #{'Result-Code' => [?UNABLE_TO_COMPLY]}.

experimental(Code) ->
    #{'Experimental-Result' =>
          [#{'Vendor-Id' => ?VENDOR_3GPP, 'Experimental-Result-Code' => Code}]}.

%% --- grouped builders (arity: RAND/XRES/AUTN/KASME bare; Item-Number list) ---
eutran_vector(I, #{rand := R, xres := X, autn := A, kasme := K}) ->
    #{'Item-Number' => [I], 'RAND' => R, 'XRES' => X, 'AUTN' => A, 'KASME' => K}.

%% Minimal Subscription-Data (M1): Subscriber-Status, AMBR, APN-Configuration-Profile.
subscription_data(Profile) ->
    Base = #{'Subscriber-Status' => [0]},   %% 0 = SERVICE_GRANTED
    WithAmbr =
        case maps:get(<<"ambr">>, Profile, undefined) of
            #{<<"ul">> := Ul, <<"dl">> := Dl} ->
                Base#{'AMBR' => [#{'Max-Requested-Bandwidth-UL' => Ul,
                                   'Max-Requested-Bandwidth-DL' => Dl}]};
            _ -> Base
        end,
    case maps:get(<<"apn_config_profile">>, Profile, undefined) of
        #{<<"context_id">> := Ctx} ->
            Apn = #{'Context-Identifier' => Ctx, 'PDN-Type' => 0,
                    'Service-Selection' => <<"default">>},
            WithAmbr#{'APN-Configuration-Profile' =>
                          [#{'Context-Identifier' => Ctx,
                             'All-APN-Configurations-Included-Indicator' => [0],
                             'APN-Configuration' => [Apn]}]};
        _ -> WithAmbr
    end.

enumerate(L) -> lists:zip(lists:seq(0, length(L) - 1), L).

%% --- helpers ---
first([])      -> #{};
first([H | _]) -> H.

first_int([], Default) -> Default;
first_int([N | _], _)  -> N.

%% Re-Synchronization-Info is RAND(16) ++ AUTS(14).
resync([])          -> undefined;
resync([<<Rand:16/binary, Auts:14/binary>> | _]) -> {Rand, Auts};
resync([_Other | _]) -> undefined.
