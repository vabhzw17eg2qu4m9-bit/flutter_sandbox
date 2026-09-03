## 0.1.6 (2026-09-03)

- chore: re-sync resource_limits/tool_policy formatting with FAH upstream (v0.1.286) (#9)

## 0.1.5 (2026-09-03)

- chore: add Release/License/pub-points badges (match fah_hub_client set) (#8)

## 0.1.4 (2026-09-03)

- chore: add pub/CRAP/coverage badges to README (match FAH style) (#7)

## 0.1.3 (2026-09-03)

- ci: make auto-release push race-tolerant (#6)

## 0.1.2 (2026-09-03)

- chore(deps): bump actions/setup-python from 5 to 7 (#4)
- chore(deps): bump actions/checkout from 4 to 7 (#3)
- chore(deps): bump actions/upload-artifact from 4 to 7 (#2)
- chore: rename docs/ to doc/ (pub package layout convention) (#5)

## 0.1.1 (2026-09-03)

- feat(cube): extract fa_cube sandbox subsystem into standalone flutter_sandbox package (#1)
- chore: initialize repository

# Changelog

## 0.1.0

- Extracted the `fa_cube` sandbox subsystem verbatim from flutter_agent_harness into a standalone package.
- Ported byte-for-byte (import rewrites only) so flutter_agent_harness can adopt this package and delete its own copies.
- New `fsb` CLI: `run`, `validate`, `wrap`, `backends` — run any console command inside a cube.
- Kernel backends: macOS `sandbox-exec` SBPL profiles, Linux `unshare` user namespaces; Windows descriptor-only.
- Quality gates carried over: pre-commit hook (analyze, format, tests, coverage), CI workflow, release binaries on tags.
