# fugit — agent integration guide

> **Audience:** AI coding agent (Claude, Codex, Cursor, etc.) working in a *parent* repo that consumes fugit as a git submodule. Not for editing fugit itself.
>
> **Editing this file:** requires a PR to `toggle-corp/fugit` upstream. `CLAUDE.md` is a pointer to this file; do not edit it independently.

fugit ships shared release and helm tooling, pulled into parent repos as a git submodule:

- `scripts/release.sh` — changelog generation (git-cliff) + signed tag. GitHub & Gitea hosts.
- `scripts/helm-update-snapshots.sh` — `helm template` snapshot testing (update + diff modes).
- `scripts/sub-module-sync.sh` — pins the submodule to the tag declared in `.gitmodules`.
- `configs/cliff.toml` — shared `git-cliff` config.

## Decision tree

| User intent | Section |
|---|---|
| Add fugit to a new repo | [Add fugit as submodule](#add-fugit-as-submodule) |
| Bump fugit version | [Update fugit](#update-fugit) |
| Set up `release.sh` / changelog + tag flow | [Add release.sh](#add-releasesh) |
| Set up helm template snapshot tests | [Add helm-update-snapshots](#add-helm-update-snapshots) |
| Render changelog from CI (e.g. populate GitHub Release body on tag push) | [Render cliff.toml in CI](#render-clifftoml-in-ci) |
| Auto-publish a Gitea Release entry on tag push | [Auto-publish Gitea releases via Woodpecker](#auto-publish-gitea-releases-via-woodpecker) |
| Something is broken | [Troubleshooting](#troubleshooting) |

## Rules (apply to every section)

- Always pin the submodule to a tag in `.gitmodules`. Never track a moving branch like `main`.
- Never `git checkout` inside the submodule directly to change versions — use `sub-module-sync.sh` so `.gitmodules` stays the source of truth.
- Files mutated inside `RELEASE_CUSTOM_HOOK` must be `git add`-ed inside the hook, or the released tag will point at the **old** version of those files. See [Hook contract](#hook-contract).
- `typos` and the `FUGIT_REMOTE_*_URL` env vars must be present anywhere `cliff.toml` is evaluated (local `release.sh` and any CI render). Missing either fails silently — see [Render cliff.toml in CI](#render-clifftoml-in-ci).

---

## Add fugit as submodule

**Preconditions:**

- Working from the parent repo root.

1. Add submodule at path `./fugit` over HTTPS (so CI and read-only clones work without SSH keys):
   ```bash
   git submodule add https://github.com/toggle-corp/fugit.git ./fugit
   ```
2. Resolve latest released tag:
   ```bash
   git -C fugit tag --sort=-v:refname | head -1
   ```
3. Pin that tag in `.gitmodules`. Add a `branch = <tag>` line and a top-of-file comment so future maintainers find the sync script. `branch` accepts a tag name — `sub-module-sync.sh` resolves it.
   ```
   # Sync this with ./fugit/scripts/sub-module-sync.sh
   [submodule "fugit"]
       path = fugit
       url = https://github.com/toggle-corp/fugit.git
       branch = v<X.Y.Z>
   ```
4. Sync to the pinned tag using fugit's own script. The script prompts `Proceed? [y/N]`; pipe `y` for non-interactive:
   ```bash
   bash fugit/scripts/sub-module-sync.sh <<< "y"
   ```
5. Verify and commit:
   ```bash
   git submodule status      # expect: <sha> fugit (v<X.Y.Z>)
   git add .gitmodules fugit
   git commit -m "chore: add fugit submodule pinned at v<X.Y.Z>"
   ```

> **Pitfall:** Don't `git checkout` inside `fugit/` to change versions — `.gitmodules` won't reflect the new pin. Always use `sub-module-sync.sh`.

---

## Update fugit

**Preconditions:** fugit already added as submodule.

1. Bump the `branch = vX.Y.Z` line in `.gitmodules` to the new tag.
2. Run `bash fugit/scripts/sub-module-sync.sh`.
3. Commit the updated submodule pointer and `.gitmodules`.

---

## Add release.sh

`fugit/scripts/release.sh` is the entrypoint. The parent repo provides a thin `release.sh` wrapper at its root that exports config and forwards args. Two hosts are supported: **GitHub** (default) and **Gitea** (via `FUGIT_HOST_TYPE=gitea`).

**Preconditions:**

- Common tools on `$PATH`: `git-cliff`, `semver`, `typos`.
- Repo is standalone (not a submodule itself).
- GitHub path: `gh` on `$PATH`, `gh auth login` complete (provides `GITHUB_TOKEN`).
- Gitea path: `GITEA_TOKEN` exported in your shell — *not* the wrapper, since it's a secret. Create one at `https://<gitea-host>/user/settings/applications`.

1. Resolve `START_COMMIT` (root commit unless an archived changelog covers earlier history):
   ```bash
   git rev-list --max-parents=0 HEAD
   ```
2. **Pick `VERSION_TAG_PREFIX_MODE` — ask the user before writing the wrapper.** This controls the tag shape `release.sh` produces, which downstream tools may or may not accept.

   | Mode | Tag shape | Use when |
   |---|---|---|
   | `require` *(default)* | `vX.Y.Z` | Git-only repo, or you strip `v` inside `RELEASE_CUSTOM_HOOK` before writing it anywhere strict |
   | `forbid` | `X.Y.Z` | The version flows directly into a helm `Chart.yaml` `version:` field, or you want OCI/SemVer-strict docker tags |
   | `ignore` | either accepted | Migration period; not recommended for new repos |

   Downstream toolchain compatibility:
   - **Helm `Chart.yaml`** — strict SemVer; `v1.2.3` is **rejected** by `helm package`/`helm install`. Either use `forbid`, or strip `v` inside the hook (`chart_version="${version_tag#v}"`).
   - **Docker / OCI image tags** — both shapes work as tag strings, but OCI artifact references and most registry tooling treat the version as plain SemVer (no `v`). Prefer `forbid` if image tags are derived from `$version_tag`.
   - **Git / GitHub Releases / Gitea Releases / git-cliff** — both shapes work.

   Explicitly export the chosen mode in the wrapper (templates below) so the choice is visible.
3. Create `release.sh` at the repo root using the matching template below.
4. `chmod +x release.sh`.
5. Commit: `chore: add release.sh using fugit`.

### Template — GitHub host (default)

No `FUGIT_HOST_TYPE` or `FUGIT_REMOTE_*_URL` needed — fugit derives URLs from the owner/repo vars.

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
export VERSION_TAG_PREFIX_MODE=<require|forbid|ignore>   # see step 2

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
export VERSION_TAG_PREFIX_MODE=<require|forbid|ignore>   # see step 2

export FUGIT_HOST_TYPE=gitea
export FUGIT_REMOTE_BASE_URL=https://<gitea-host>/<owner>/<repo>
export FUGIT_REMOTE_PLATFORM_URL=https://<gitea-host>

export GIT_CLIFF__REMOTE__GITEA__OWNER=<owner>
export GIT_CLIFF__REMOTE__GITEA__REPO=<repo>
export GIT_CLIFF__REMOTE__GITEA__API_URL=https://<gitea-host>/api/v1

"$SCRIPT_DIR/fugit/scripts/release.sh" "${@:-}"
```

> **Pitfall (Gitea only):** Without `GITEA_TOKEN`, Gitea returns null fields where git-cliff expects sequences, causing a deserializer panic. Export it in your shell.

### Hook contract

`scripts/release.sh` stages **only** `CHANGELOG.md` before its release commit (literally `git add CHANGELOG.md && git commit -m ...`, no `-a`). Anything the hook writes to the working tree is invisible to that commit and to the tag created immediately after, so the released tag will point at the **old** version of every file the hook touched.

Stage the files inside the hook itself:

```bash
function release_custom_hook {
    # Bump the chart version baked into the tag.
    # Strip any leading `v` — helm Chart.yaml `version:` is strict SemVer.
    # Safe under both VERSION_TAG_PREFIX_MODE=require and =forbid (no-op on plain SemVer).
    chart_version="${version_tag#v}"
    sed -i.bak "s/^version: .*/version: $chart_version/" deploy/helm/chart/Chart.yaml
    rm -f deploy/helm/chart/Chart.yaml.bak

    # REQUIRED: stage the mutation. Without this, the next `git commit`
    # in fugit's release.sh will not pick it up.
    git add deploy/helm/chart/Chart.yaml
}
```

The hook receives no arguments; the version is in the surrounding shell's `$version_tag` (set by fugit before the hook runs).

> **Pitfall:** Forgetting `git add` inside the hook is the most common failure. The tag ends up pointing at unbumped files, and nothing visibly errors.

### Variables

- `START_COMMIT` — git-cliff range start. Bump only when archiving old changelogs (also update `cliff.toml:footer`).
- `REPO_NAME` — display only, used in error messages.
- `DEFAULT_BRANCH` — `release.sh` warns if you run from another branch.
- `RELEASE_CUSTOM_HOOK` — function name run before changelog generation. Use it to bump versions in `pyproject.toml`, `package.json`, `Chart.yaml`, etc. See [Hook contract](#hook-contract).
- `FUGIT_HOST_TYPE` — `github` (default) or `gitea`. Selects the auth path. Only needed for Gitea.
- `FUGIT_REMOTE_BASE_URL` — full repo URL for changelog commit/PR/compare links. **Required for Gitea**; auto-derived from `GIT_CLIFF__REMOTE__GITHUB__{OWNER,REPO}` for GitHub.
- `FUGIT_REMOTE_PLATFORM_URL` — host root for contributor profile links. **Required for Gitea**; defaults to `https://github.com` for GitHub.
- `GIT_CLIFF__REMOTE__GITHUB__{OWNER,REPO}` — required on the GitHub path. Used for both API enrichment and URL auto-derivation.
- `GIT_CLIFF__REMOTE__GITEA__{OWNER,REPO,API_URL}` — required on the Gitea path. `API_URL` mandatory for self-hosted Gitea.
- `VERSION_TAG_PREFIX_MODE` (default `require`) — `require` (vX.Y.Z), `forbid` (X.Y.Z), or `ignore`. Choose based on downstream toolchain — helm `Chart.yaml` rejects the `v` prefix, OCI/docker tags prefer plain SemVer. See step 2 of [Add release.sh](#add-releasesh).

### Usage

```bash
./release.sh                # prompts for version
./release.sh v1.2.3         # pre-fills v1.2.3 in prompt
```

Writes `CHANGELOG.md`, commits it, creates a signed tag. After it finishes: `git push origin <tag>` then `git push`.

---

## Add helm-update-snapshots

`fugit/scripts/helm-update-snapshots.sh` renders `helm template` for each configured test and either writes a snapshot or diffs against the existing one. The parent repo provides a thin `helm/update-snapshots.sh` wrapper.

**Preconditions:**

- `yq` and `helm` on `$PATH` (script aborts via `check_yq` / `check_helm`).
- Wrapper exports `SCRIPT_DIR` — the inner script does `cd "$SCRIPT_DIR"` and aborts on unset (`SCRIPT_DIR=${SCRIPT_DIR?error}`).
- Helm chart lives in the wrapper's parent dir — script runs `helm template ./` from `$SCRIPT_DIR`.

1. Create `helm/update-snapshots.sh`:
   ```bash
   #!/bin/bash

   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   export SCRIPT_DIR

   # shellcheck disable=SC2068
   "$SCRIPT_DIR/../fugit/scripts/helm-update-snapshots.sh" "$@"
   ```
2. `chmod +x helm/update-snapshots.sh`.
3. Create `helm/tests.yaml`. Each key names a snapshot; its list is the complete, ordered set of values files layered on the chart's `values.yaml`. A trailing `.yaml` on the key is optional:
   ```yaml
   tests:
     alpha.yaml:                     # -> snapshots/alpha.yaml
       - values/operators/dragonfly.yaml
       - values/alpha.yaml
       - values/traefik.yaml
     staging:                        # -> snapshots/staging.yaml
       - values/operators/dragonfly.yaml
       - values/staging.yaml
       - tests/go-deploy-dummy.yaml
   ```
   Keys that resolve to the same snapshot name (`prod` and `prod.yaml`) are rejected before anything renders.
4. Put values a snapshot needs but a real deployment supplies (dummy image tags, hosts, secrets) under `helm/tests/`, and **list them in `tests.yaml`** like any other file — nothing under `helm/tests/` is included implicitly, and one dummy file can be shared by several tests. Position in the list decides precedence.
5. Generate the first snapshots:
   ```bash
   ./helm/update-snapshots.sh
   ```
   Output goes to `helm/snapshots/<key-without-yaml>.yaml`.
6. Commit `tests.yaml`, `tests/`, and `snapshots/`.

> **Upgrading from ≤ v0.2.0:** the script used to append `helm/tests/<key>` to every test automatically. It no longer does. Where such a file exists but is unlisted the script now errors out naming it — add it to that test's list (usually last, matching the old precedence) or delete it.

### Usage

```bash
./helm/update-snapshots.sh                       # write/refresh snapshots
./helm/update-snapshots.sh --check-diff-only     # CI mode: exit non-zero if stale
./helm/update-snapshots.sh --check-diff-only --diff-cmd 'delta --paging=never'
```

`--diff-cmd` accepts either `--diff-cmd=<cmd>` or `--diff-cmd <cmd args...>` (collects words until the next `--flag`). Default is `diff -u`.

### Variables

- `CUSTOM_HELM_NAMESPACE` (optional, default `default`) — sets `HELM_NAMESPACE` for the `helm template` invocation.
- `SCRIPT_DIR` (required, exported by wrapper) — the inner script `cd`s here before rendering.

### CI — GitHub Actions

Fail PRs that drift from committed snapshots:

```yaml
- name: Install yq
  uses: dcarbone/install-yq-action@v1

- name: Set up Helm
  uses: azure/setup-helm@v4

- name: Check helm snapshots
  run: ./helm/update-snapshots.sh --check-diff-only
```

> **Pitfall:** Forgetting `export SCRIPT_DIR` in the wrapper. Plain assignment (`SCRIPT_DIR=...`) is not enough; the inner script reads it from the environment and aborts on unset.

> **Pitfall:** Values precedence follows list order, last wins. A file appended after an environment overlay (e.g. `values/traefik.yaml`) overrides it — reorder the list rather than editing the overlay.

---

## Render cliff.toml in CI

You can run `git-cliff` against `fugit/configs/cliff.toml` from a CI workflow to render a fresh changelog — e.g. to populate a GitHub Release body on tag push, separate from the `CHANGELOG.md` that `release.sh` committed locally. The config uses two `replace_command` features that require setup on the runner; get any of them wrong and the output looks plausibly correct but is silently broken.

**Preconditions:**

- `typos` available on the runner.
- `FUGIT_REMOTE_BASE_URL` and `FUGIT_REMOTE_PLATFORM_URL` exported to the git-cliff step.

### 1. `typos` must be on `$PATH`

`cliff.toml`'s commit preprocessor runs `typos --write-changes -` against every commit message. If `typos` is missing, the preprocessor exits non-zero and **git-cliff silently drops the affected commits** — the rendered output keeps the version header but the body is empty.

```yaml
- name: Install typos
  uses: taiki-e/install-action@v2
  with:
    tool: typos
```

`typos` matches the local-dev requirement `release.sh` already checks for.

### 2. URL env vars must be exported to git-cliff

`cliff.toml`'s changelog postprocessors substitute `<REPO>` / `<REPO_PLATFORM_URL>` placeholders with real URLs via shell `sed`. Without the env vars, sed substitutes with empty strings, leaving literal `<REPO>/commit/<sha>` strings throughout the rendered body.

```yaml
- name: Generate changelog
  uses: orhun/git-cliff-action@v4
  with:
    config: fugit/configs/cliff.toml
    args: -vv --latest --strip all --github-repo ${{ github.repository }}
  env:
    OUTPUT: CHANGELOG.latest.md
    FUGIT_REMOTE_BASE_URL: https://github.com/${{ github.repository }}
    FUGIT_REMOTE_PLATFORM_URL: https://github.com
```

For Gitea paths, set both URLs to your Gitea host.

### 3. Do NOT pass `--no-exec` to git-cliff

`--no-exec` disables ALL `replace_command` directives at once — both the postprocessors above AND the typos preprocessor. With `--no-exec` you get literal `<REPO>` strings in the output, AND (if you later remove it) empty bodies until typos is installed. Local `release.sh` invokes git-cliff without `--no-exec`; CI workflows should mirror that.

> **Pitfall:** All three failures above produce plausible-looking output. Eyeball one full rendered changelog after wiring CI for the first time.

---

## Auto-publish Gitea releases via Woodpecker

`release.sh` only creates the local tag; Gitea won't surface a Release entry until one is created via UI or API. To automate, add a Woodpecker pipeline triggered on tag push that calls Gitea's release API.

**Preconditions:**

- Woodpecker connected to the Gitea repo.
- Dedicated bot account (see step 1) — *don't* use your personal token.

1. **Create a bot user, not your own.** Gitea (≤1.26 at time of writing) doesn't support per-repo token scoping — `write:repository` granted to any user-token applies to every repo that user can access. To limit blast-radius:
   - Create a bot user (e.g. `togglecorp-ci`) in Gitea.
   - Add the bot as a Collaborator with **Write** access on this repo only.
   - Sign in as the bot at `https://<gitea-host>/user/settings/applications` and create a token with `write:repository` scope.
2. In Woodpecker (repo settings → Secrets), add a secret named `gitea_token` with the bot's token value. Limit it to the `tag` event for blast-radius.
3. Commit `.woodpecker/release.yml` (Woodpecker 2.x/3.x syntax):
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

Trigger: `git push origin <tag>` after `release.sh` finishes. Woodpecker picks up the tag event, extracts the message body from the signed tag, and creates the Gitea release.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `git-cliff` deserializer panic (Gitea path) | `GITEA_TOKEN` not exported; unauthenticated API returns null where sequences expected | `export GITEA_TOKEN=<token>` in your shell |
| Rendered changelog has version header but empty body | `typos` missing on `$PATH`; commit preprocessor exits non-zero and git-cliff silently drops commits | Install `typos` (locally and in CI) |
| Rendered changelog contains literal `<REPO>/commit/<sha>` strings | `FUGIT_REMOTE_BASE_URL` / `FUGIT_REMOTE_PLATFORM_URL` not exported to git-cliff | Export both env vars to the git-cliff step |
| Released tag points at old version of `Chart.yaml` / `pyproject.toml` / etc. that the hook should have bumped | `release_custom_hook` mutated files but didn't `git add` them | Add `git add <file>` inside the hook |
| `helm-update-snapshots.sh` aborts with `SCRIPT_DIR: error` | Wrapper assigned `SCRIPT_DIR` but did not `export` it | Add `export SCRIPT_DIR` in the wrapper |
| `helm-update-snapshots.sh` errors: `tests/<key> exists but is not listed` | Auto-inclusion of `helm/tests/<key>` was removed after v0.2.0 | List the file in that test's `tests.yaml` entry (last, to keep the old precedence) or delete it |
| Two `tests.yaml` keys rejected as writing the same snapshot | Keys differ only by the optional `.yaml` suffix (`prod` vs `prod.yaml`) | Rename one key |
| Submodule pointer drifts from `.gitmodules` `branch =` tag | Someone ran `git checkout` inside `fugit/` instead of `sub-module-sync.sh` | Re-run `bash fugit/scripts/sub-module-sync.sh` |
| `helm package` / `helm install` rejects `v1.2.3` as invalid SemVer in `Chart.yaml` | `VERSION_TAG_PREFIX_MODE=require` produces `v`-prefixed tags; helm `version:` requires plain SemVer | Switch to `VERSION_TAG_PREFIX_MODE=forbid`, or strip `v` inside the hook (`chart_version="${version_tag#v}"`) before writing `Chart.yaml` |
