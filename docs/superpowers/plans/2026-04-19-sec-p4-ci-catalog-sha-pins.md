# SEC-P4-14: Pin ci-catalog Components by Commit SHA

> Referenced by GAP_ANALYSIS.md (SEC-P4-14) and GitLab issue #188.
> Status: BLOCKED-EXTERNAL — requires an operator-supplied tag→SHA map
> for `gitlab.com/devnw/ci-catalog` (no read credentials from this repo's
> automation context).

## Problem

`.gitlab-ci.yml` includes 8 CI catalog components pinned by moving tags
(`@v1.7.1` ×7, `@v1.2.1` ×1). A moved tag executes unreviewed code in this
project's CI with release/SBOM privileges (CWE-494/CWE-1357, OWASP A03).

## Prerequisite (operator action)

Run, with ci-catalog read access:

```bash
git ls-remote https://gitlab.com/devnw/ci-catalog.git \
  refs/tags/v1.7.1 refs/tags/v1.2.1
```

Record the two commit SHAs.

## Steps (once SHAs are supplied)

1. In `.gitlab-ci.yml`, replace each `@v1.7.1` with `@<sha-of-v1.7.1>` and
   `zig-format@v1.2.1` with `@<sha-of-v1.2.1>`, keeping the tag in a
   trailing comment: `# v1.7.1`.
2. Push a branch; confirm all 8 components still resolve (GitLab resolves
   component refs by SHA identically to tags) and the pipeline is green.
3. Record the tag→SHA map and rotation procedure in
   `docs/runbooks/ci-catalog-sha-rotation.md` (create it from this plan's
   steps; fold in the H-1 APT-pin note per the appsec report).
4. Close SEC-P4-14 (#188) with the pipeline evidence; mark H-1 resolved in
   the same commit if the runbook lands.

## Rotation procedure (future upgrades)

On each ci-catalog release: re-run the `git ls-remote` above for the new
tag, review the component diff between the old and new SHAs, update the 8
pins in one commit titled `ci: bump ci-catalog to <tag> (<sha>)`.
