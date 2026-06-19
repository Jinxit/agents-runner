# Custom ArcUI fleet runner images.
#
# Two targets, both layered on the upstream eloylp agents-runner:
#
#   runner          — tweakcc model-customizations patch only.
#   runner-wowless  — tweakcc + Lua 5.1 toolchain + pre-built wowless binary
#                     with TACT client data for headless WoW addon testing.
#
# Build a specific target with:
#   docker build --target runner          -t agents-runner:dev .
#   docker build --target runner-wowless  -t agents-runner-wowless:dev .
#
# BASE is pinned to an immutable digest for reproducible builds. The
# base-image sync agent bumps this digest via PR when the upstream
# eloylp/agents-runner:latest tag advances; do not change it by hand.
ARG BASE=ghcr.io/eloylp/agents-runner@sha256:970667ea659579da20cd94596814a510a25fc2ef5fb987c0f61f2d3a5f3beb9d

# ── wowless builder ──────────────────────────────────────────────────────────
# Clones latest wowless HEAD and builds wowless_wow with vcpkg/cmake, including
# TACT client data download. The resulting binary + data are copied into the
# runner-wowless target; all build tooling stays in this stage.
#
# BuildKit cache mounts persist vcpkg downloads and binary-cached packages
# across builds via the GHA cache backend (mode=max exports exec.cachemount
# data alongside layer cache). Since `git clone --depth 1` always fetches
# HEAD, the layer cache is invalidated on every new wowless commit — but the
# vcpkg cache mounts survive the layer miss, skipping the expensive
# dependency download + compile even when the source changes.
#
# BuildKit only processes this stage when the runner-wowless target is
# requested; builds targeting runner skip it entirely.
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

# Collect the binary and the runtime data it resolves via CWD-relative paths:
#   build/products/    — TACT data + WowlessData addon
#   build/*.sqlite3    — schema and data databases
#   build/extracts/    — FrameXML (for non-lite mode)
#   build/addon/       — wowless internal addon
# A compat symlink /opt/wowless/products -> build/products preserves the path
# used by the CI "Log WoW build number" step.
RUN mkdir -p /opt/wowless/build \
    && WOW_BIN=$(find build -name "wowless_wow" -type f -not -path "*/products/*") \
    && cp "$WOW_BIN" /opt/wowless/wowless_wow \
    && chmod +x /opt/wowless/wowless_wow \
    && cp -r build/products build/extracts build/addon /opt/wowless/build/ \
    && cp build/*.sqlite3 /opt/wowless/build/ \
    && ln -s build/products /opt/wowless/products

# ── runner (tweakcc only) ────────────────────────────────────────────────────
# tweakcc patches the installed Claude Code binary (a native compiled bundle) to
# expose all available models in the /model picker. The version is pinned; bump
# it deliberately alongside Claude Code version upgrades. If tweakcc does not yet
# support the installed CC version the build will fail loudly — intentional.
FROM ${BASE} AS runner

USER root
RUN npx -y tweakcc@4.0.14 --apply --patches model-customizations
USER agents

# ── runner-wowless (tweakcc + lua + wowless) ─────────────────────────────────
# Adds Lua 5.1 (luac + luacheck) for WoW addon linting and a pre-built wowless
# binary with TACT client data for headless addon testing.
#
# WoW runs Lua 5.1, so luac 5.1 matches the in-game parser exactly. luacheck
# should be configured with std = "lua51" in the consuming repo's .luacheckrc.
#
# wowless must be invoked from /opt/wowless/ so it finds runtime data at the
# expected CWD-relative paths:
#   cd /opt/wowless && ./wowless_wow run -p wow --addondir /path/to/addons
FROM runner AS runner-wowless

COPY --from=wowless-builder /opt/wowless /opt/wowless

USER root
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 \
    && luarocks-5.1 install luacheck
USER agents
