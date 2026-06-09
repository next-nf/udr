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
%% S6a/S6d flag-AVP bit masks (TS 29.272). The *-Flags AVPs are integer bitmasks
%% on the wire; these name the individual bits so code and tests never use raw
%% literals. Each macro is the mask (the value with that single bit set).
-ifndef(S6A_FLAGS_HRL).
-define(S6A_FLAGS_HRL, true).

%% ULR-Flags (TS 29.272 7.3.7)
-define(ULR_FLAG_SKIP_SUBSCRIBER_DATA, 16#4).   %% bit 2
-define(ULR_FLAG_INITIAL_ATTACH,       16#20).  %% bit 5

%% PUA-Flags (TS 29.272 7.3.48)
-define(PUA_FLAG_FREEZE_M_TMSI,        16#1).   %% bit 0

%% DSR-Flags (TS 29.272 7.3.25)
-define(DSR_FLAG_REGIONAL_SUBSCRIPTION_WITHDRAWAL, 16#1).  %% bit 0

-endif.
