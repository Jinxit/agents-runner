# agents-runner

Custom runner image for the ArcUI fleet, managed by the
[agents](https://github.com/eloylp/agents) daemon.

It is a thin layer on top of the upstream
[`ghcr.io/eloylp/agents-runner`](https://github.com/eloylp/agents) image,
adding the Lua 5.1 toolchain so fleet agents can syntax-check and lint World of
Warcraft addon Lua before opening pull requests.

## What it adds

- `lua5.1` / `luac` — WoW runs Lua 5.1, so `luac -p` matches the in-game parser
  exactly. This avoids false passes from newer Lua versions, which accept syntax
  (`goto`, `//`, bitwise operators, `<const>` / `<close>`) that WoW rejects at
  load time.
- `luacheck` — static linter. Configure with `std = "lua51"` plus the addon's
  WoW globals in the consuming repository's `.luacheckrc`.

Everything else (Claude Code, Codex, `gh`, git, Go, Rust, Node, TypeScript)
comes from the upstream base image.

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
