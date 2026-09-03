<!-- Keep it short. Sections that don't apply can be removed. -->

## Summary

What does this PR change, and why?

## Verification

- `fsb --version`: <!-- e.g. fsb 0.1.0 -->
- Platform: <!-- e.g. macOS 15 (arm64) / Ubuntu 24.04 (x64) / Windows 11 -->

If this changes runtime behavior, include the cube YAML and the wrapped command:

```yaml
# minimal cube YAML reproducing the behavior
```

```bash
fsb run --cube <name> -- <command...>
```

## Checklist

- [ ] `scripts/pre-commit` gates pass (or CI is green)
- [ ] Ported `lib/src/cube/` + `lib/src/env/` code stays byte-identical to flutter_agent_harness (import rewrites only)
- [ ] Docs updated for user-visible changes
