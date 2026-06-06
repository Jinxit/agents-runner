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
#   cd /opt/wowless && ./wowless_wow run -p wow --addondir /path/to/addons
# The binary embeds all Lua code (via lua2c) but needs runtime data on disk,
# resolved relative to CWD via hardcoded `build/...` paths:
#   build/wow_schema.sqlite3        — WoW schema DB (always needed)
#   build/wow_data.sqlite3          — WoW data DB (needed without --lite)
#   build/products/<product>/       — TACT product data + WowlessData addon
#   build/extracts/<product>/       — extracted FrameXML (needed without --lite)
# A compat symlink /opt/wowless/products -> build/products is kept so the
# build workflow can read build info at the previously documented path.
#
# BASE is pinned to an immutable digest for reproducible builds. The
# base-image sync agent bumps this digest via PR when the upstream
# eloylp/agents-runner:latest tag advances; do not change it by hand.
ARG BASE=ghcr.io/eloylp/agents-runner@sha256:970667ea659579da20cd94596814a510a25fc2ef5fb987c0f61f2d3a5f3beb9d

# ── wowless builder ──────────────────────────────────────────────────────────
# Clones latest wowless HEAD and builds wowless_wow with vcpkg/cmake, including
# TACT client data download. The resulting binary + data are copied into the
# final image; all build tooling stays in this stage.
#
# BuildKit cache mounts persist vcpkg downloads and binary-cached packages
# across builds. Since `git clone --depth 1` always fetches HEAD, the layer
# cache is invalidated on every new wowless commit — but the vcpkg caches
# survive, skipping the expensive dependency download + compile.
FROM alpine:3 AS wowless-builder

RUN apk add --no-cache \
    bash cmake curl g++ gcompat git linux-headers make musl-dev \
    ninja perl pkgconf python3 tar unzip zip

WORKDIR /build/wowless
RUN git clone --depth 1 https://github.com/wowless/wowless.git .
RUN git submodule update --init --depth 1
RUN --mount=type=cache,target=/root/.cache/vcpkg \
    --mount=type=cache,target=/build/wowless/vcpkg/downloads \
    cmake --preset default
RUN --mount=type=cache,target=/root/.cache/vcpkg \
    --mount=type=cache,target=/build/wowless/vcpkg/downloads \
    cmake --build --preset default --target wowless_wow wow

RUN mkdir -p /opt/wowless/build \
    && WOW_BIN=$(find build -name "wowless_wow" -type f -not -path "*/products/*") \
    && cp "$WOW_BIN" /opt/wowless/wowless_wow \
    && chmod +x /opt/wowless/wowless_wow \
    && cp -r build/products /opt/wowless/build/products \
    && ln -sfn build/products /opt/wowless/products \
    && find build -maxdepth 1 -name "*.sqlite3" -exec cp {} /opt/wowless/build/ \; \
    && if [ -d build/extracts ]; then cp -r build/extracts /opt/wowless/build/extracts; fi \
    && if [ -d build/addon ]; then cp -r build/addon /opt/wowless/build/addon; fi

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
