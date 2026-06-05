# Custom ArcUI fleet runner image.
#
# Thin layer on top of the upstream eloylp agents-runner. Adds the Lua 5.1
# toolchain (luac + luacheck) so fleet agents can syntax-check and lint WoW
# addon Lua before opening pull requests.
#
# WoW runs Lua 5.1, so luac 5.1 matches the in-game parser exactly. luacheck
# should be configured with std = "lua51" (plus the addon's WoW globals) in the
# consuming repository's .luacheckrc.
#
# The base image already ships build-base, and the lua5.1 package provides the
# unversioned `lua` / `luac` binaries on PATH, so no extra setup is required.
#
# BASE is pinned to an immutable digest for reproducible builds. The
# base-image sync agent bumps this digest via PR when the upstream
# eloylp/agents-runner:latest tag advances; do not change it by hand.
ARG BASE=ghcr.io/eloylp/agents-runner@sha256:970667ea659579da20cd94596814a510a25fc2ef5fb987c0f61f2d3a5f3beb9d
FROM ${BASE}

USER root
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 \
    && luarocks-5.1 install luacheck
USER agents
