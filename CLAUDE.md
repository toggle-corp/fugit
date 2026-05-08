# fugit — Claude integration guide

This file teaches Claude how to add `fugit` as a git submodule to a new repo and keep it in sync.

## Adding fugit to a new repository

Run from the parent repo root:

1. Add submodule via SSH at path `./fugit`:
   ```bash
   git submodule add git@github.com:toggle-corp/fugit.git ./fugit
   ```

2. Resolve latest released tag:
   ```bash
   git -C fugit tag --sort=-v:refname | head -1
   ```

3. Pin that tag in `.gitmodules` by adding a `branch = <tag>` line under the `[submodule "fugit"]` block. `branch` accepts a tag name; `sub-module-sync.sh` resolves it. Also add a top-of-file comment so future maintainers find the sync script:
   ```
   # Sync this with ./fugit/scripts/sub-module-sync.sh
   [submodule "fugit"]
       path = fugit
       url = git@github.com:toggle-corp/fugit.git
       branch = v<X.Y.Z>
   ```

4. Sync the submodule to the pinned tag using fugit's own script (do NOT `git checkout` manually):
   ```bash
   bash fugit/scripts/sub-module-sync.sh
   ```
   Script prompts `Proceed? [y/N]`. Pipe `y` for non-interactive: `bash fugit/scripts/sub-module-sync.sh <<< "y"`.

5. Verify and commit:
   ```bash
   git submodule status      # expect: <sha> fugit (v<X.Y.Z>)
   git add .gitmodules fugit
   git commit -m "chore: add fugit submodule pinned at v<X.Y.Z>"
   ```

## Updating fugit to a newer version

1. Bump the `branch = vX.Y.Z` line in `.gitmodules` to the new tag.
2. Re-run `bash fugit/scripts/sub-module-sync.sh`.
3. Commit the updated submodule pointer + `.gitmodules`.

## Adding `release.sh` to a new repository

`fugit/scripts/release.sh` is the real entrypoint. The parent repo provides a thin `release.sh` wrapper at its root that exports config and forwards args. fugit supports two hosts: **GitHub** and **Gitea** (selected via `FUGIT_HOST_TYPE`).

Steps from the parent repo root:

1. Resolve `START_COMMIT` (root commit unless an archived changelog covers earlier history):

   ```bash
   git rev-list --max-parents=0 HEAD
   ```

2. Create `release.sh` at the repo root using one of the templates below.

### Template — GitHub host (default)

GitHub is the default. No `FUGIT_HOST_TYPE` or `FUGIT_REMOTE_*_URL` needed — fugit derives the URLs from the owner/repo vars.

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

function release_custom_hook {
    echo ""
}

export -f release_custom_hook
export START_COMMIT=<root-commit-sha>
export RELEASE_CUSTOM_HOOK=release_custom_hook
export REPO_NAME=<owner>/<repo>
export DEFAULT_BRANCH=main

export GIT_CLIFF__REMOTE__GITHUB__OWNER=<owner>
export GIT_CLIFF__REMOTE__GITHUB__REPO=<repo>

"$SCRIPT_DIR/fugit/scripts/release.sh" "${@:-}"
```

### Template — Gitea host (incl. self-hosted)

```bash
#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

function release_custom_hook {
    echo ""
}

export -f release_custom_hook
export START_COMMIT=<root-commit-sha>
export RELEASE_CUSTOM_HOOK=release_custom_hook
export REPO_NAME=<owner>/<repo>
export DEFAULT_BRANCH=main

export FUGIT_HOST_TYPE=gitea
export FUGIT_REMOTE_BASE_URL=https://<gitea-host>/<owner>/<repo>
export FUGIT_REMOTE_PLATFORM_URL=https://<gitea-host>

export GIT_CLIFF__REMOTE__GITEA__OWNER=<owner>
export GIT_CLIFF__REMOTE__GITEA__REPO=<repo>
export GIT_CLIFF__REMOTE__GITEA__API_URL=https://<gitea-host>/api/v1

"$SCRIPT_DIR/fugit/scripts/release.sh" "${@:-}"
```

`GITEA_TOKEN` is required — without it, Gitea returns null fields where git-cliff expects sequences, causing a deserializer panic. Export it in your shell (not the wrapper, since it's a secret). Create one at `https://<gitea-host>/user/settings/applications`.

3. `chmod +x release.sh`.

4. Commit: `chore: add release.sh using fugit`.

### Variables — what each does

- `START_COMMIT` — git-cliff range start. Bump only when archiving old changelogs (also update `cliff.toml:footer`).
- `REPO_NAME` — display only, used in error messages.
- `DEFAULT_BRANCH` — release.sh warns if you run from another branch.
- `RELEASE_CUSTOM_HOOK` — function name run before changelog generation. Use it to bump versions in `pyproject.toml`, `package.json`, etc., and `git add` those files so they go into the release commit.
- `FUGIT_HOST_TYPE` — `github` (default) or `gitea`. Selects the auth path. Only needed for Gitea.
- `FUGIT_REMOTE_BASE_URL` — full repo URL for changelog commit/PR/compare links. **Required for Gitea**; auto-derived from `GIT_CLIFF__REMOTE__GITHUB__{OWNER,REPO}` for GitHub.
- `FUGIT_REMOTE_PLATFORM_URL` — host root for contributor profile links. **Required for Gitea**; defaults to `https://github.com` for GitHub.
- `GIT_CLIFF__REMOTE__GITHUB__{OWNER,REPO}` — required on the GitHub path. Used for both API enrichment and URL auto-derivation.
- `GIT_CLIFF__REMOTE__GITEA__{OWNER,REPO,API_URL}` — required on the Gitea path. `API_URL` mandatory for self-hosted Gitea.
- `VERSION_TAG_PREFIX_MODE` (optional, default `require`) — `require` (vX.Y.Z), `forbid` (X.Y.Z), or `ignore`.

### Requirements (release.sh checks these)

Common: `git-cliff`, `semver`, `typos` on `$PATH`. Repo standalone (not a submodule itself).

- GitHub path: `gh` on `$PATH`, `gh auth login` completed (provides `GITHUB_TOKEN`).
- Gitea path: `GITEA_TOKEN` env var exported (unauthenticated calls return malformed JSON for git-cliff).

### Usage

```bash
./release.sh                # prompts for version
./release.sh v1.2.3         # pre-fills v1.2.3 in prompt
```

Script writes `CHANGELOG.md`, commits it, and creates a signed tag. After it finishes: `git push origin <tag>` then `git push`.

## Auto-publishing Gitea releases via Woodpecker CI

`release.sh` only creates the local tag; Gitea won't surface a Release entry until one is created via UI or API. To automate, add a Woodpecker pipeline triggered on tag push that calls Gitea's release API.

Pipeline file (`.woodpecker/release.yml`) — Woodpecker 2.x/3.x syntax:

```yaml
when:
  - event: tag

steps:
  - name: extract-notes
    image: alpine/git
    commands:
      # subject + body, excluding the PGP signature block
      - git tag -l --format='%(contents:subject)%0a%0a%(contents:body)' "$CI_COMMIT_TAG" > .release-notes.md

  - name: create-release
    image: woodpeckerci/plugin-gitea-release
    settings:
      base_url: https://<gitea-host>
      api_key:
        from_secret: gitea_token
      title: ${CI_COMMIT_TAG}
      note: .release-notes.md
```

Setup once per repo:

1. **Use a dedicated bot account, not your own.** Gitea (≤1.26 at the time of writing) doesn't support per-repo token scoping — `write:repository` granted to any user-token applies to every repo that user can access. To limit blast-radius:
   - Create a bot user (e.g. `togglecorp-ci`) in Gitea.
   - Add the bot as a Collaborator with **Write** access on this repo only.
   - Sign in as the bot at `https://<gitea-host>/user/settings/applications` and create a token with `write:repository` scope.
2. In Woodpecker (repo settings → Secrets), add a secret named `gitea_token` with the bot's token value. Limit it to the `tag` event for blast-radius.
3. Commit `.woodpecker/release.yml`.

Trigger: `git push origin <tag>` after `release.sh` finishes. Woodpecker picks up the tag event, extracts the message body from the signed tag, and creates the Gitea release.

## Rules

- Use HTTPS URL
- Always pin to a tag in `.gitmodules`. Never track a moving branch like `main`.
- Never `git checkout` inside the submodule directly to change versions — use `sub-module-sync.sh` so `.gitmodules` stays the source of truth.
- Editing this file requires a PR to `toggle-corp/fugit` upstream.
