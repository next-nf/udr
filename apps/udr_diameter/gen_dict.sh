#!/bin/sh
# Generate the S6a Diameter dictionary module from its .dia source using OTP's
# own dictionary compiler (diameter_make, shipped with the diameter app). This
# replaces the third-party rebar3_diameter_compiler plugin, which does not build
# on OTP-29.
#
# Invoked from apps/udr_diameter/rebar.config as a compile pre_hook. rebar3 runs
# hook commands through open_port/spawn, which does NOT interpret shell operators
# (&&, ;, |, redirects) -- only a single program runs -- so all multi-step logic
# lives here, in one script, run as a single command.
#
# We cd into the script's own directory so the relative paths below resolve
# regardless of the caller's working directory.
set -e
cd "$(dirname "$0")"

# diameter_make:codec/2 writes both the .erl and the .hrl into {outdir}. The
# @inherits diameter_gen_base_rfc6733 base dictionary is resolved from the
# diameter application on the code path, so no {include,...} option is needed.
erl -noshell \
    -eval 'case diameter_make:codec("dia/diameter_3gpp_s6a.dia", [{outdir, "src"}]) of ok -> ok; E -> io:format(standard_error, "diameter codec failed: ~p~n", [E]), halt(1) end' \
    -s init stop

# Keep the original layout: .erl in src/ (compiled by rebar3), .hrl in include/.
mkdir -p include
mv -f src/diameter_3gpp_s6a.hrl include/diameter_3gpp_s6a.hrl
