# agents-runner

Custom runner image for the ArcUI fleet, managed by the
[agents](https://github.com/eloylp/agents) daemon.

It is a thin layer on top of the upstream
[`ghcr.io/eloylp/agents-runner`](https://github.com/eloylp/agents) image,
adding the Lua 5.1 toolchain and a tweakcc patch to the Claude Code binary.

## What it adds

- `lua5.1` / `luac` — WoW runs Lua 5.1, so `luac -p` matches the in-game parser
  exactly. This avoids false passes from newer Lua versions, which accept syntax
  (`goto`, `//`, bitwise operators, `<const>` / `<close>`) that WoW rejects at
  load time.
- `luacheck` — static linter. Configure with `std = "lua51"` plus the addon's
  WoW globals in the consuming repository's `.luacheckrc`.
- **tweakcc `model-customizations` patch** — unlocks the full Claude model list
  in `claude`'s `/model` picker. Without this patch only the default three models
  are shown; with it every available model is selectable.

Everything else (Claude Code, Codex, `gh`, git, Go, Rust, Node, TypeScript)
comes from the upstream base image.

## tweakcc layer

[tweakcc](https://github.com/Piebald-AI/tweakcc) patches the Claude Code native
binary at image build time. The `model-customizations` patch (`id:
model-customizations`) enables all Claude models in the `/model` picker.

### Version coupling

tweakcc matches patterns inside the CC binary, so it is tied to the specific
Claude Code version installed by the base image. When the base-image sync bumps
the CC version, tweakcc re-runs against the new binary. If tweakcc has not yet
added support for that CC version the Docker build **fails loudly** — this is
intentional and preferable to a silent bad patch.

**To recover from a mismatch:**
1. Check the [tweakcc releases](https://github.com/Piebald-AI/tweakcc/releases)
   for a version that supports the new CC release.
2. Update the pinned `tweakcc@<version>` in the `Dockerfile` accordingly.
3. Open a PR with both the base-image digest bump and the tweakcc version bump.

To revert the patch for debugging, run `npx tweakcc@<pinned-version> --restore`
inside a container built from the base image (before the tweakcc layer).

## Build

The image builds and pushes automatically via GitHub Actions on every push to
`main` and on `v*` tags. Images are published to
`ghcr.io/jinxit/agents-runner` with immutable per-commit tags
(`sha-<shortsha>`), a `v*` tag for releases, and a moving `latest` on `main`.

To build locally:

```sh
docker build -t agents-runner:dev .
```

Pin the base to a digest for a fully reproducible build:

```sh
docker build --build-arg BASE=ghcr.io/eloylp/agents-runner@sha256:<digest> -t agents-runner:dev .
```

## Using it in the fleet

The daemon pulls the runner image without registry authentication, so the GHCR
package must be **public** (the source repository may remain private — package
visibility is set independently).

Point the fleet at a specific immutable tag rather than `latest` so rolls are
deliberate. Set `runner_image` as a per-workspace override on the ArcUI
workspace (Config → Runtime, REST, or the agents-fleet MCP):

```
ghcr.io/jinxit/agents-runner:sha-<shortsha>
```

To roll forward to a new build, bump that tag to the newer `sha-` (or `v*`) tag.
