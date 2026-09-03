# Changelog

## 0.1.0

- Extracted the `fa_cube` sandbox subsystem verbatim from flutter_agent_harness into a standalone package.
- Ported byte-for-byte (import rewrites only) so flutter_agent_harness can adopt this package and delete its own copies.
- New `fsb` CLI: `run`, `validate`, `wrap`, `backends` — run any console command inside a cube.
- Kernel backends: macOS `sandbox-exec` SBPL profiles, Linux `unshare` user namespaces; Windows descriptor-only.
- Quality gates carried over: pre-commit hook (analyze, format, tests, coverage), CI workflow, release binaries on tags.
