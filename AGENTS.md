# AGENTS.md

Conventions for AI agents and contributors in this repository. Keep it
factual: paths, commands, invariants — no essays.

## What this is

`flutter_sandbox` — the fa_cube sandbox subsystem extracted verbatim from
flutter_agent_harness (FAH) so it can be reused standalone. The `fsb` CLI
runs ANY console command inside a policy or kernel sandbox: macOS
`sandbox-exec` (SBPL), Linux `unshare` (user namespaces), Windows Job
Object descriptor, or no-op.

FAH can adopt this package and delete its own cube + env-foundation
copies — that swap-back only works if the ported code stays byte-identical.

## Identity policy (ported code)

- `lib/src/cube/`, `lib/src/env/` and their tests are a VERBATIM MIRROR of
  the FAH upstream. The only allowed diff vs the FAH source is the import
  URI rewrite (`package:flutter_agent_harness/...` →
  `package:flutter_sandbox/...`).
- Renames are FORBIDDEN: keep the exact `fa_cube[` enforcement prefix and
  the `.fah/` state paths (`.fah/cubes`, `.fah/cube-cache`,
  `.fah/cube-profiles`, `.fah/tmp`) in code, strings, tests, and docs.
  Spec-format identifiers are unchanged too: apiVersion `fa/v1`, kind
  `Cube`, `Cube*` class names, `$id urn:fa:cube:fa-v1`.
- Keep all comments, including `// ignore_for_file:` lines and `ponytail:`
  notes.
- Minimize drift so upstream changes can be re-synced by diff. New
  standalone functionality lives in `bin/`, `lib/src/cli/`, and their
  tests — never inside ported files.

## Project layout

- `lib/src/cube/` — cube subsystem: strict YAML `CubeSpec` → policies
  (tools/network/fs/env/resources/cache, deny-wins, empty-allow =
  deny-all) → runtime (`CubeResolver`, `CubePolicyEngine` lexical bash
  scanner, `CubeFsGuard`, `SandboxedShell` kernel wrap, `CubeCacheManager`
  content-addressed cache) → backends (macOS SBPL, Linux unshare argv,
  Windows descriptor, no-op).
- `lib/src/env/` — the portability boundary: `ExecutionEnv` =
  `FileSystem` (13 methods) + `Shell` (exec) + optional `BackgroundShell`.
- `lib/src/cli/` — the standalone `fsb` runner (`run`, `validate`, `wrap`,
  `backends`). CLI-level usage/spec-resolution errors may use an `fsb: `
  prefix; ported-behavior output stays verbatim (denials: `fa_cube[...]`
  prefix + exit 127; resolver: `cube: file not found: ...`).
- `bin/fsb.dart` — the executable entry point (may use `dart:io`).
- `schema/` — JSON schema for cube manifests. `docs/` — user docs.
  `test/` — mirrors `lib/`.

## Hard rules

- `lib/` is PURE DART: no `dart:io`. `dart:io` is allowed only in `bin/`
  and in files exported through `lib/io.dart`; everything else takes an
  injected `ExecutionEnv`. Nothing in `lib/` may reach the host machine
  outside that boundary.
- No dart file over 2800 lines (excluding `*.g.dart`).

## Commands

- `dart test` — all tests, including the integration e2e suite (it
  self-skips where the platform lacks kernel support); gates pass
  `--exclude-tags integration`.
- `dart test --tags integration` — kernel live tests; self-skip without
  user namespaces.
- `dart test --coverage=coverage` then
  `dart run coverage:format_coverage --lcov -i coverage -o
  coverage/lcov.info` — coverage.
- `python3 scripts/check_coverage.py 80` — coverage ratchet (lib/).
- `cp scripts/pre-commit .git/hooks/pre-commit && chmod +x
  .git/hooks/pre-commit` — install the gate.

## Quality gates (pre-commit + CI)

1. File size ≤ 2800 lines per dart file (excl. `*.g.dart`).
2. `dart analyze` + self-healing `dart format` of staged files.
3. `dart test --coverage=coverage --exclude-tags integration`.
4. Line coverage of `lib/` ≥ 80%.
5. CRAP ratchet — `crap4dart.yaml` threshold 12.0, only-down.
6. Duplication (jscpd, `--min-tokens 50 --min-lines 5`) over `lib/` < 1.4%
   (baseline at extraction 1.39% — clones live in verbatim-ported upstream
   files; ratchet only-down).

## Commits

`type(scope): summary` — types `fix`/`feat`/`chore`. Merges to main are
auto-released: the CI release job bumps the patch version, prepends
CHANGELOG, pushes an annotated `vX.Y.Z` tag and builds binaries;
`chore(release):` commits are the loop guard.
