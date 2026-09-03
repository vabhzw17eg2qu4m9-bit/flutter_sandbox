# flutter_sandbox

[![CI](https://github.com/vabhzw17eg2qu4m9-bit/flutter_sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/vabhzw17eg2qu4m9-bit/flutter_sandbox/actions/workflows/ci.yml)

Standalone command sandboxing: the `fa_cube` sandbox subsystem extracted
verbatim from flutter_agent_harness, shipped as a reusable package and a
standalone `fsb` binary. Run any console command inside a declarative
sandbox profile — a **cube**. A cube is a strict YAML manifest that clamps
which commands may execute, which hosts may be reached, which paths may be
touched, which environment variables the run sees, and how much time and
disk the run may consume. Manifests live in `.fah/cubes/<name>.yaml` and
the binary keeps its state (`.fah/cube-cache/`, `.fah/cube-profiles/`,
`.fah/tmp/`) under the workspace cwd.

**Swap-back intent.** The ported code is a byte-for-byte mirror of the FAH
upstream: flutter_agent_harness can add this package as a dependency,
point its cube and env-foundation imports here, and delete its own
copies.

Manifests are parsed **strictly**: a wrong `apiVersion`, a bad name, or an
unknown key at any level is a loud startup error — a broken manifest never
fails open into an unconfined run.

## Install

Download a prebuilt `fsb` binary from
[GitHub Releases](https://github.com/vabhzw17eg2qu4m9-bit/flutter_sandbox/releases),
or:

```sh
dart pub global activate flutter_sandbox
```

## Quickstart

Save a cube to `.fah/cubes/web-scraper.yaml`:

```yaml
apiVersion: fa/v1
kind: Cube
metadata:
  name: web-scraper
  description: "Fetches documentation pages and extracts text."
spec:
  tools:
    allow: [curl, wget, "git*"]
    deny: ["git push"]
  network:
    allow:
      - {host: "*.example.com", ports: [80, 443]}
      - {host: api.github.com, ports: [443]}
    deny:
      - {host: "*", ports: [22, 3389]}
  filesystem:
    workspace: /workspace
    mounts:
      - {path: /usr/share/doc, access: ro}
      - {path: ~/.ssh, access: deny}
  env:
    - {name: FAH_MODE, value: sandboxed}
    - {name: SCRAPER_KEY, valueFrom: "env:API_KEY"}
    - {name: HOME, hidden: true}
  resources:
    limits: {cpu: "50%", memory: 512Mi, disk: 100Mi}
    timeout: 3600s
  cache:
    enabled: true
    paths: [/workspace/.cache]
    restore: true
    ttl: 24h
```

Run a command inside it:

```sh
fsb run --cube web-scraper -- curl -s https://docs.example.com/index.html
```

Denials fail closed: exit code 127 with an `fa_cube[<name>]:` reason on
stderr.

## Commands

| Command | Effect |
|---|---|
| `fsb run --cube <name> \| --cube-config <path> [--backend policy\|kernel] [--workspace <dir>] [--timeout <seconds>] -- <cmd...>` | Run a command inside the cube. Cache restore before, save after; exit code passes through. |
| `fsb validate <path>` | Strictly parse a manifest; report every error. |
| `fsb wrap --cube <name> \| --cube-config <path> [--workspace <dir>] -- <cmd...>` | Print the kernel-wrapped command for inspection. |
| `fsb backends` | Describe the platform sandbox backend. |

## Backends

| Platform | Backend | Mode |
|---|---|---|
| macOS | `sandbox-exec` SBPL profile | Kernel |
| Linux | `unshare` user namespace (`--net` when nothing is allowed) | Kernel |
| Windows | Job Object descriptor | Descriptor-only |
| Any | Dart policy checks | Policy |

`--backend kernel` selects the hard OS boundary in addition to the Dart
policy layer; `--backend policy` (default) enforces in Dart only.

## Enforcement layers

**The Dart policy layer is a convenience, not a boundary.** The command
scanner is quote-aware but not a shell parser, the network scan sees only
`curl`/`wget` operands, and env stripping is additive-only in policy mode.
The kernel sandbox backends are the hard boundary; where kernel mode is
unavailable (Windows, unsupported kernels), there is no hard boundary.
Denials are refused, not audited. See the confinement contract in
[docs/cubes.md](docs/cubes.md).

## Development

```sh
cp scripts/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
dart test
```

The pre-commit gate runs analyze, format checks, the test suite with
coverage (>= 80% of `lib/`), and copy-paste detection. Integration-tagged
tests are excluded by default: `dart test --tags integration` runs them.

The full cube manifest reference lives in [docs/cubes.md](docs/cubes.md).
