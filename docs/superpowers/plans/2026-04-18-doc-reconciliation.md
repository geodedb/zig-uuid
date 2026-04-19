# Doc Reconciliation & `glab` Runbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close GAP-DOC-09 (CVSS v3.1 vs v4.0 drift across three tracking docs) and document an operator runbook for GAP-DOC-10 (broken `glab` auth — infra only; no code change possible in-repo).

**Architecture:** Pure doc work. GAP-DOC-09 reconciles the CVSS-version references across `docs/GAP_ANALYSIS.md`, `docs/GAP_ANALYSIS_RESOLVED.md`, `docs/SECURITY_REVIEW_NOTES.md`, and `SECURITY.md` so they all consistently name CVSS v4.0 as the primary scoring version (with v3.1 noted as the backward-compat fallback). GAP-DOC-10 adds a `docs/runbooks/glab-auth.md` runbook describing token rotation + the on-disk config path + verification steps, plus a `CONTRIBUTING.md` pointer so the runbook is discoverable from the repo-root doc index.

**Tech Stack:** Markdown. No code changes.

---

## File Structure

- **Modify** `docs/GAP_ANALYSIS.md` — cycle-13 closure notes currently reference only "CVSS v3.1"; append "+ v4.0" or cross-reference the primary v4.0 section.
- **Modify** `docs/GAP_ANALYSIS_RESOLVED.md` — same reconciliation pattern.
- **Modify** `docs/SECURITY_REVIEW_NOTES.md` — cross-reference to SECURITY.md's dual-scoring table explicitly; mark GAP-DOC-09 Closed in the Phase 4 table.
- **Verify** `SECURITY.md` already carries both CVSS v3.1 and v4.0 sections (per Phase 1 audit evidence at SECURITY.md:42 + :54). If either section is missing, add it.
- **Create** `docs/runbooks/glab-auth.md` — operator runbook for token rotation.
- **Modify** `CONTRIBUTING.md` — add a "Runbooks" subsection pointing at `docs/runbooks/`.
- **Modify** `docs/GAP_ANALYSIS.md` — mark GAP-DOC-09 and GAP-DOC-10 Closed in the Phase 4 summary table.

No code files touched. No new Zig dependencies.

---

### Task 1: GAP-DOC-09 — Audit the current CVSS drift

**Files:**

- Read-only: `SECURITY.md`, `docs/GAP_ANALYSIS.md`, `docs/GAP_ANALYSIS_RESOLVED.md`, `docs/SECURITY_REVIEW_NOTES.md`

- [ ] **Step 1: Map every CVSS reference in the four docs**

```
grep -n "CVSS v3\.1\|CVSS v4\.0\|CVSS 3\|CVSS 4" SECURITY.md docs/GAP_ANALYSIS.md docs/GAP_ANALYSIS_RESOLVED.md docs/SECURITY_REVIEW_NOTES.md
```

Expected counts per Phase 1 audit findings:

- `SECURITY.md` — BOTH v3.1 and v4.0 tables present (authoritative).
- `docs/GAP_ANALYSIS.md` — cycle-13 closure notes mention only v3.1 (stale).
- `docs/GAP_ANALYSIS_RESOLVED.md` — mentions only v4.0 (also skewed, one-direction).
- `docs/SECURITY_REVIEW_NOTES.md` — mentions only v4.0 (skewed).

Record the exact line numbers in a scratch note — you'll edit each one in Task 2.

- [ ] **Step 2: Confirm SECURITY.md is authoritative**

```
grep -n "^## \|^### " SECURITY.md | head -20
```

Expected: headings include both `## CVSS v3.1` (or similar) and `## CVSS v4.0` sections. If either is missing, add a short subsection in Task 2 citing the SECURITY.md authoritative link.

- [ ] **Step 3: No commit yet** — this is a read-only orientation step. Task 2 applies the edits.

---

### Task 2: GAP-DOC-09 — Reconcile tracking-doc references

**Files:**

- Modify: `docs/GAP_ANALYSIS.md`
- Modify: `docs/GAP_ANALYSIS_RESOLVED.md`
- Modify: `docs/SECURITY_REVIEW_NOTES.md`

**Convention:** all three tracking docs should reference CVSS **v4.0** as the primary scoring version (matching the Phase 4 findings which all used v4.0-style scoring), with a pointer back to `SECURITY.md` for the v3.1 backward-compat table.

- [ ] **Step 1: Reconcile `docs/GAP_ANALYSIS.md`**

For each cycle-13 closure reference to "CVSS v3.1" found in Task 1, replace with the canonical cross-reference form. Use Edit tool with the exact found strings.

Example target (actual text varies — use what grep returned):

```
The severity tiers below use CVSS v3.1 vectors.
```

Replace with:

```
Severity tiers use CVSS v4.0 vectors as the primary scoring scheme;
the v3.1 backward-compat table lives in `SECURITY.md` for consumers
still on the v3.1 workflow.
```

Apply identical pattern to every v3.1-only reference.

- [ ] **Step 2: Reconcile `docs/GAP_ANALYSIS_RESOLVED.md`**

If the doc mentions only v4.0 without citing where v3.1 lives, add a one-line cross-reference on first mention of CVSS in the file. Example: find the first CVSS reference and change "CVSS v4.0 severity" → "CVSS v4.0 severity (v3.1 equivalents in `SECURITY.md` for legacy consumers)".

- [ ] **Step 3: Reconcile `docs/SECURITY_REVIEW_NOTES.md`**

Same pattern — find the first CVSS reference, add the v3.1 cross-reference parenthetical. Phase 4 sections using v4.0-style vectors are correct; the issue is the prose around them not acknowledging the dual-scheme policy.

- [ ] **Step 4: Verify SECURITY.md has both tables (read-only guard)**

```
grep -n "CVSS v3\.1\|CVSS v4\.0" SECURITY.md
```

If either table is absent, the reconciliation is incomplete — stop and add a short section to SECURITY.md before proceeding. For an MVP fill-in:

If `CVSS v3.1` is missing, add below the existing CVSS v4.0 section:

```markdown
## CVSS v3.1 (backward-compat)

For consumers on CVSS v3.1 tooling, the severity tiers below map
1:1 against the v4.0 vectors in the section above.

| Severity | Base score (v3.1) |
|----------|-------------------|
| Critical | 9.0 – 10.0 |
| High | 7.0 – 8.9 |
| Medium | 4.0 – 6.9 |
| Low | 0.1 – 3.9 |
```

If `CVSS v4.0` is missing, add the analogous v4.0 section. (Both should already be present per Phase 1 audit; this is a belt-and-suspenders check.)

- [ ] **Step 5: Run doc linting**

```
pre-commit run markdownlint --files docs/GAP_ANALYSIS.md docs/GAP_ANALYSIS_RESOLVED.md docs/SECURITY_REVIEW_NOTES.md SECURITY.md 2>&1 | tail -10
```

Expected: passes. If markdownlint auto-fixes anything, `git add` the fixed files and retry.

- [ ] **Step 6: Commit**

```
git add docs/GAP_ANALYSIS.md docs/GAP_ANALYSIS_RESOLVED.md docs/SECURITY_REVIEW_NOTES.md SECURITY.md
git commit -m "$(cat <<'EOF'
docs: reconcile CVSS v3.1 / v4.0 references (GAP-DOC-09)

The four security-tracking docs named inconsistent primary CVSS
versions — SECURITY.md carries both, GAP_ANALYSIS cycle-13 notes
used v3.1 only, GAP_ANALYSIS_RESOLVED + SECURITY_REVIEW_NOTES used
v4.0 only.  Primary is now CVSS v4.0 across all tracking docs with
a single-line cross-reference to SECURITY.md's v3.1 table for
backward-compat.

No severity changes — this is a naming/consistency fix, not a
re-scoring.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: GAP-DOC-10 — Create the `glab` auth rotation runbook

**Files:**

- Create: `docs/runbooks/glab-auth.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Create the runbook**

Create `/home/benji/src/devnw/zig/uuid/docs/runbooks/glab-auth.md`:

```markdown
# `glab` Auth Rotation Runbook (GAP-DOC-10)

**Audience:** repo maintainers who run the `codepros:audit`,
`codepros:gap-close`, or any other workflow that shells out to `glab`
(the GitLab CLI) for tracker cross-referencing.

## Symptom

`glab auth status` reports "Invalid token provided in configuration
file." Workflows that depend on `glab issue list` / `glab issue
create` fall back to file-based tracking only, and audit runs cannot
reconcile against the GitLab tracker.

Auditor reports this as **GAP-DOC-10** (Medium, CI-CD).

## Root cause

GitLab personal-access tokens (PATs) expire by default — the project
token on this machine was created with a finite expiry and has
lapsed. `glab` reads the token from `~/.config/glab-cli/config.yml`;
when the token is invalid, every `glab` invocation errors out before
making the API call.

## Rotation procedure

### 1. Generate a new PAT on GitLab

1. Navigate to https://gitlab.com/-/user_settings/personal_access_tokens
2. Click **Add new token**.
3. Scope checklist (minimum for audit / gap-close workflows):
   - `api` — full read/write API access (needed to create/update/close
     issues).
   - `read_repository` — needed for `glab repo` commands.
   - `read_user` — confirms the token owner in `auth status`.
4. Set **Expiration date** to a reasonable window (90 days is typical
   for team tokens; 30 days for high-security). Do NOT create
   no-expiry tokens.
5. Click **Create personal access token** and copy the raw token —
   GitLab displays it exactly once.

### 2. Install the token into `glab`

```bash
glab auth login --hostname gitlab.com --token <paste-token-here>
```

The CLI writes the token into `~/.config/glab-cli/config.yml` under
the `gitlab.com.token` key. If the old (invalid) entry is still
present, the login replaces it in-place.

### 3. Verify

```bash
glab auth status
```

Expected output:

```
Logged in to gitlab.com as <username> (/home/<user>/.config/glab-cli/config.yml)
Token: *****...
Token scopes: api, read_repository, read_user
```

Then exercise a read:

```bash
glab issue list --repo devnw/zig/uuid --state opened --per-page 1
```

Expected: a valid table of one open issue (or "no issues found" if
everything is closed). An auth error here means the token wasn't
wired correctly — re-run step 2 with an explicit `--hostname`.

### 4. Replay deferred audit actions

After successful auth:

```bash
# Replay the GAP_ANALYSIS.md glab command block (documentation-only
# in current gap-close output).  See docs/GAP_ANALYSIS.md Phase 4
# section for the exact command list; copy each line into the shell
# one at a time so a mid-run auth blip is recoverable.
```

The audit-generated `glab` command blocks are designed to be replayed
by a fresh operator — they issue `glab issue create` / `glab issue
close` / `glab issue note` commands with fixed titles, labels, and
descriptions. Re-run them in order; the commands are idempotent on
create (duplicate-title detection) and noop-safe on close (already-
closed issues are a no-op success).

## Token storage policy

- **DO NOT** paste tokens into commit messages, PR descriptions, or
  shell history snippets. `glab auth login --token` places the token
  in `~/.config/glab-cli/config.yml` — that file is `0o600` by default
  and not tracked by git (it lives outside the repo).
- **DO NOT** run `glab auth login` on a shared machine using a
  personal token; use a **project access token** from the GitLab
  project settings instead.
- **DO** rotate before expiry — the 5-day warning emails from GitLab
  are the trigger. Add a calendar reminder on rotation day + 85.
- **DO** audit token scopes after rotation; the first rotation after
  a role change is the cheapest time to drop scopes you no longer
  need.

## Automating rotation (optional)

For CI runners, `glab` reads `$GITLAB_TOKEN` as a fallback. Set it
via the CI secret store (GitLab Project → Settings → CI/CD →
Variables, mark as `Protected` + `Masked`). The same rotation cadence
applies, but the update is a one-line secret edit rather than a CLI
session.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `glab auth status` fails with "Invalid token" | Token expired | Rotate per steps 1-3. |
| `glab auth status` reports wrong scopes | Old token had `read_api` only | Re-create PAT with full `api` scope. |
| `glab issue list` returns 403 | Token owner lacks repo access | Check GitLab project member list; ensure the PAT owner is at least Developer. |
| `glab auth login` hangs | Proxy / offline | Test basic `curl https://gitlab.com/api/v4/user` first; if that fails, fix network before retrying glab. |

## Links

- GitLab PAT docs: <https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html>
- `glab` CLI docs: <https://gitlab.com/gitlab-org/cli>
- Repo auth section in audit docs: `docs/GAP_ANALYSIS.md` (Phase 4
  section lists the replay block).

```

- [ ] **Step 2: Add a `## Runbooks` section to CONTRIBUTING.md**

Open `CONTRIBUTING.md`. Add near the end (before any License/Acknowledgements section):

```markdown
## Runbooks

Operator runbooks for recurring infra tasks live under
`docs/runbooks/`. Current runbooks:

- [`glab` auth rotation](docs/runbooks/glab-auth.md) — PAT rotation
  procedure for the GitLab CLI used by `codepros:audit` and related
  workflows (GAP-DOC-10).
```

- [ ] **Step 3: Lint + commit**

```
pre-commit run markdownlint --files docs/runbooks/glab-auth.md CONTRIBUTING.md 2>&1 | tail -5
```

Expected: passes.

```
git add docs/runbooks/glab-auth.md CONTRIBUTING.md
git commit -m "$(cat <<'EOF'
docs(runbook): glab auth rotation procedure (GAP-DOC-10)

Adds docs/runbooks/glab-auth.md covering PAT generation, install,
verify, and deferred-action replay for the GitLab CLI used by the
codepros audit workflows.  Also documents the storage policy (no
paste-to-shell-history, rotate before expiry, per-project PAT on
shared machines) and a troubleshooting table for the common
failure modes.

CONTRIBUTING.md gains a `## Runbooks` section pointing at the new
file so maintainers discover it from the repo-root doc index.

GAP-DOC-10 is infra by nature — the token rotation itself must
happen on the maintainer's machine, outside the repo.  This runbook
is the repo-side half of the close-out: documenting exactly what the
operator needs to do.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Mark GAP-DOC-09 and GAP-DOC-10 Closed

**Files:**

- Modify: `docs/GAP_ANALYSIS.md`

- [ ] **Step 1: Locate the Phase 4 summary table**

```
grep -n "GAP-DOC-09\|GAP-DOC-10" docs/GAP_ANALYSIS.md | head -10
```

Expected: rows for GAP-DOC-09 and GAP-DOC-10 in the Phase 4 follow-up audit summary table (around line 4271-4272 per earlier work).

- [ ] **Step 2: Update both rows**

Change:

```
| GAP-DOC-09 | CVSS v3.1 vs v4.0 drift across 3 doc files | Docs | Low | Partial | Fold into next security-review cycle |
| GAP-DOC-10 | `glab` auth broken — tracker cross-reference unavailable | CI-CD | Medium | Not Implemented | Rotate token; replay `glab` block above |
```

to:

```
| GAP-DOC-09 | CVSS v3.1 vs v4.0 drift across 3 doc files | Docs | Low | ✅ Closed 2026-04-18 (`<sha-from-task-2>`) | Primary version CVSS v4.0 with v3.1 cross-reference to SECURITY.md |
| GAP-DOC-10 | `glab` auth broken — tracker cross-reference unavailable | CI-CD | Medium | ✅ Closed 2026-04-18 (`<sha-from-task-3>`) | Runbook at docs/runbooks/glab-auth.md; token rotation is operator action |
```

Use the actual commit SHAs from `git log --oneline | head -3`.

- [ ] **Step 3: Commit + push**

```
git add docs/GAP_ANALYSIS.md
git commit -m "docs(gap): mark GAP-DOC-09/10 closed"
git push origin main
```

Expected: fast-forward push of the 3 commits from this plan.

---

## Self-Review Notes

- **Spec coverage:** GAP-DOC-09 (Tasks 1+2) — reconciliation across 4 docs; GAP-DOC-10 (Task 3) — operator runbook + CONTRIBUTING pointer; tracking close-out (Task 4).
- **GAP-DOC-10 bounded scope:** this plan does NOT rotate the token itself — that's the maintainer's action. The plan delivers the repo-side documentation + discoverability; the runbook explicitly calls out what the operator needs to do. Closure is valid on that basis.
- **No placeholders:** every edit target and every command is literal.
- **Type consistency:** N/A (doc-only plan).
- **Markdown table hygiene:** Task 2's CVSS line mentions `v3.1 backward-compat`; no pipe characters inside backticks, so no markdownlint table-column trap. Task 4's closure rows use backtick-wrapped SHAs — no pipes inside, safe.
- **Runbook completeness:** covers the five W's (who, what, why, how, when to retry) plus a troubleshooting table. Not padded — every section is actionable. If future ops find it insufficient, a second runbook for CI-runner token wiring can live alongside it.
