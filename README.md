# agents-runner

Custom runner images for the ArcUI fleet, managed by the
[agents](https://github.com/eloylp/agents) daemon.

Two variants are published, both layered on the upstream
[`ghcr.io/eloylp/agents-runner`](https://github.com/eloylp/agents) image:

| Image | What it adds |
|-------|-------------|
| `ghcr.io/jinxit/agents-runner` | tweakcc model-customizations patch |
| `ghcr.io/jinxit/agents-runner-wowless` | tweakcc + Lua 5.1 toolchain + pre-built wowless |

## tweakcc

tweakcc patches the Claude Code native binary at image build time. The
`model-customizations` patch enables all Claude models in the `/model` picker
instead of just the default three.

The version is pinned in the Dockerfile; bump it deliberately alongside Claude
Code version upgrades. If tweakcc does not yet support the installed CC version
the Docker build **fails loudly** — this is intentional and preferable to a
silent bad patch.

**To recover from a mismatch:**
1. Check the tweakcc releases for a version that supports the new CC release.
2. Update the pinned `tweakcc@<version>` in the `Dockerfile` accordingly.
3. Open a PR with both the base-image digest bump and the tweakcc version bump.

To revert the patch for debugging, run `npx tweakcc@<pinned-version> --restore`
inside a container built from the base image (before the tweakcc layer).

## Wowless layer

The `-wowless` variant adds:

- `lua5.1` / `luac` — WoW runs Lua 5.1, so `luac -p` matches the in-game parser
  exactly. This avoids false passes from newer Lua versions, which accept syntax
  (`goto`, `//`, bitwise operators, `<const>` / `<close>`) that WoW rejects at
  load time.
- `luacheck` — static linter. Configure with `std = "lua51"` plus the addon's
  WoW globals in the consuming repository's `.luacheckrc`.
- **wowless** — headless WoW client Lua/FrameXML interpreter, pre-built with
  TACT client data. Invoke as:
  ```sh
  cd /opt/wowless && ./wowless_wow run -p wow --addondir /path/to/addons
  ```

## Build

Both images build and push automatically via GitHub Actions on every push to
`main` and on `v*` tags. Images are published to GHCR with immutable per-commit
tags (`sha-<shortsha>`), a `v*` tag for releases, and a moving `latest` on
`main`.

To build locally:

```sh
# Base runner (tweakcc only)
docker build --target runner -t agents-runner:dev .

# Wowless runner (tweakcc + lua + wowless)
docker build --target runner-wowless -t agents-runner-wowless:dev .
```

Pin the base to a digest for a fully reproducible build:

```sh
docker build --build-arg BASE=ghcr.io/eloylp/agents-runner@sha256:<digest> \
  --target runner -t agents-runner:dev .
```

## Using it in the fleet

The daemon pulls the runner image without registry authentication, so the GHCR
packages must be **public** (the source repository may remain private — package
visibility is set independently).

Pin a specific immutable tag rather than `latest` so rolls are deliberate. Set
`runner_image` as a per-workspace override (Config → Runtime, REST, or the
agents-fleet MCP):

```
ghcr.io/jinxit/agents-runner:sha-<shortsha>
ghcr.io/jinxit/agents-runner-wowless:sha-<shortsha>
```

To roll forward to a new build, bump that tag to the newer `sha-` (or `v*`) tag.
