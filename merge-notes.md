# merge-notes — sep-1 branch sweep (2026-09-01)

Hologram starter app scaffold. Swept per the 2026-09-01 branch-sweep recipe (session 58fc679b).

- **Base**: `origin/develop` @98818d5 (2026-09-01) — freshest tip among origin/develop / origin/main / origin/mono-repo-dev by commit date.
- **sep-1 tag**: skip(local) (points at base tip).
- **develop**: existed+ff — trunk going forward; local main fast-forwarded to origin: no.

## Review/merge sequence
1. No open PRs and no consolidation needed for this repo — nothing to merge. `develop` is the trunk; future work branches from it.

## Skip/ignore list
- `mono-repo-dev` — stale mono-repo-era snapshot, local=remote @a989b1e, unmerged. Left intact by policy; safe to ignore, do not merge without a reconciliation pass.
- No merged branches to prune.

## Open PRs
| # | branch | base | what |
|---|--------|------|------|
| — | none | — | no open PRs in this repo |
