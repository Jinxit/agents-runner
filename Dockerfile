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
# Pin BASE to a digest for fully reproducible builds when desired:
#   --build-arg BASE=ghcr.io/eloylp/agents-runner@sha256:...
ARG BASE=ghcr.io/eloylp/agents-runner:latest
FROM ${BASE}

USER root
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 \
    && luarocks-5.1 install luacheck
USER agents
