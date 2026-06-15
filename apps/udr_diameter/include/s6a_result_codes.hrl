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

%% 3GPP S6a/S6d Experimental-Result-Codes (TS 29.272 clause 7.4) and the 3GPP
%% vendor id. These are not part of the base RFC 6733 dictionary nor emitted by
%% diameter_make, so they are defined here ONCE and included wherever needed
%% (codec + tests) rather than redefined per module. Base Result-Codes
%% (SUCCESS, UNABLE_TO_COMPLY, AUTHORIZATION_REJECTED) come from
%% diameter_gen_base_rfc6733.hrl instead.
-ifndef(S6A_RESULT_CODES_HRL).
-define(S6A_RESULT_CODES_HRL, true).

-define(VENDOR_ID_3GPP, 10415).

-define(DIAMETER_ERROR_USER_UNKNOWN,                    5001).
-define(DIAMETER_ERROR_UNKNOWN_EPS_SUBSCRIPTION,        5420).
-define(DIAMETER_ERROR_UNKNOWN_SERVING_NODE,            5423).
-define(DIAMETER_ERROR_AUTHENTICATION_DATA_UNAVAILABLE, 4181).

-endif.
