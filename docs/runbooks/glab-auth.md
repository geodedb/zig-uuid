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

1. Navigate to <https://gitlab.com/-/user_settings/personal_access_tokens>
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

```text
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
