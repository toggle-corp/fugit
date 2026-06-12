# fugit

Shared release and helm tooling for `toggle-corp` repos. Consumed by parent repos as a git submodule.

## What's here

- `scripts/release.sh` — changelog (git-cliff) + signed tag. GitHub & Gitea hosts.
- `scripts/helm-update-snapshots.sh` — `helm template` snapshot testing (update + diff modes).
- `scripts/sub-module-sync.sh` — pin the fugit submodule to the tag declared in `.gitmodules`.
- `configs/cliff.toml` — shared `git-cliff` config.

## Setup

- **AI coding agents (Claude, Codex, Cursor, etc.):** read [AGENTS.md](./AGENTS.md). It is the canonical, task-by-task recipe. `CLAUDE.md` is a pointer to the same content.
- **Humans setting up helm snapshots:** see the walkthrough in [docs/helm.md](./docs/helm.md).
- **Humans setting up releases or anything else:** [AGENTS.md](./AGENTS.md) reads cleanly for humans too — the steps are identical.
