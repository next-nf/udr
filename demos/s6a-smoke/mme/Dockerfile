# syntax=docker/dockerfile:1

# Minimal S6a Diameter MME client for the smoke demo.
#
# It needs only the S6a codec and OTP's diameter app — not the HSS or its deps —
# so instead of a full rebar3 build it generates the dictionary straight from its
# .dia source with OTP's diameter_make (the same compiler the project's build
# pre_hook uses), then compiles the dictionary and the client.
FROM erlang:29-alpine

WORKDIR /client

# The .dia dictionary source and the client. (Build context is the repo root.)
COPY apps/udr_diameter/dia/diameter_3gpp_s6a.dia ./
COPY demos/s6a-smoke/mme/smoke_mme.erl ./

RUN erl -noshell \
      -eval 'case diameter_make:codec("diameter_3gpp_s6a.dia", [{outdir, "."}]) of ok -> ok; E -> io:format(standard_error, "codec failed: ~p~n", [E]), halt(1) end' \
      -s init stop \
 && erlc diameter_3gpp_s6a.erl \
 && erlc smoke_mme.erl

ENV HSS_HOST=hss \
    HSS_PORT=3868 \
    IMSI=001010000000001 \
    NUM_VECTORS=2

ENTRYPOINT ["erl", "-noshell", "-pa", ".", "-run", "smoke_mme", "main"]
