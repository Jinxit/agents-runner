# Custom ArcUI fleet runner image.
#
#
# Thin layer on top of the upstream eloylp agents-runner. Adds the Lua 5.1
# toolchain (luac + luacheck) so fleet agents can syntax-check and lint WoW
# addon Lua before opening pull requests, applies tweakcc to unlock the full
# Claude Code model list, and ships a pre-built wowless binary with TACT client
# data so agents can run headless WoW addon tests without compiling from source.
#
# WoW runs Lua 5.1, so luac 5.1 matches the in-game parser exactly. luacheck
# should be configured with std = "lua51" (plus the addon's WoW globals) in the
# consuming repository's .luacheckrc.
#
# The base image already ships build-base, and the lua5.1 package provides the
# unversioned `lua` / `luac` binaries on PATH, so no extra setup is required.
#
# tweakcc patches the installed Claude Code binary (a native compiled bundle) to
# expose all available models in the /model picker, not just the default three.
# The version is pinned; bump it deliberately alongside Claude Code version
# upgrades. If tweakcc does not yet support the installed CC version the build
# will fail loudly — this is intentional.
#
# wowless is a headless WoW client Lua/FrameXML interpreter built in the
# wowless-builder stage and installed at /opt/wowless/. The binary is invoked as:
#   /opt/wowless/wowless_wow run -p wow --addondir /path/to/addons
# The TACT client data is stored alongside the binary under /opt/wowless/products/.
#
# BASE is pinned to an immutable digest for reproducible builds. The
# base-image sync agent bumps this digest via PR when the upstream
# eloylp/agents-runner:latest tag advances; do not change it by hand.
ARG BASE=ghcr.io/eloylp/agents-runner@sha256:970667ea659579da20cd94596814a510a25fc2ef5fb987c0f61f2d3a5f3beb9d

# ── wowless builder ──────────────────────────────────────────────────────────
# Clones latest wowless HEAD and builds wowless_wow with vcpkg/cmake, including
# TACT client data download. The resulting binary + data are copied into the
# final image; all build tooling stays in this stage.
FROM alpine:3 AS wowless-builder

RUN apk add --no-cache \
    bash cmake curl g++ gcompat git linux-headers make musl-dev \
    ninja perl pkgconf python3 tar unzip zip

WORKDIR /build/wowless
RUN git clone --depth 1 https://github.com/wowless/wowless.git .
RUN git submodule update --init --depth 1
RUN cmake --preset default
RUN cmake --build --preset default --target wowless_wow wow

RUN mkdir -p /opt/wowless \
    && WOW_BIN=$(find build -name "wowless_wow" -type f -not -path "*/products/*") \
    && cp "$WOW_BIN" /opt/wowless/wowless_wow \
    && chmod +x /opt/wowless/wowless_wow \
    && cp -r build/products /opt/wowless/

# ── final image ───────────────────────────────────────────────────────────────
FROM ${BASE}

COPY --from=wowless-builder /opt/wowless /opt/wowless

USER root
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 \
    && luarocks-5.1 install luacheck
USER agents

USER root
RUN npx -y tweakcc@4.0.14 --apply --patches model-customizations
USER agents
