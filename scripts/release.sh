#!/usr/bin/env bash
# Original https://github.com/orhun/git-cliff/blob/main/release.sh
set -eu

FUGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_utils.sh
source "${FUGIT_SCRIPT_DIR}/_utils.sh"

REPO_NAME=${REPO_NAME?error}
DEFAULT_BRANCH=${DEFAULT_BRANCH?error}

# Update this to archive old changelogs
# TODO: Make sure to also update cliff.toml:footer to includes those archived changelogs as well
START_COMMIT=${START_COMMIT:-$(git rev-list --max-parents=0 HEAD)}
RELEASE_CUSTOM_HOOK="${RELEASE_CUSTOM_HOOK?error}"
VERSION_TAG_PREFIX_MODE="${VERSION_TAG_PREFIX_MODE:-require}"

check_typos
check_git_cliff
check_semver
check_gh

log_warning "Using VERSION_TAG_PREFIX_MODE=${VERSION_TAG_PREFIX_MODE}"
echo "Generating GITHUB_TOKEN using gh (Used by git-cliff)"
GITHUB_TOKEN="$(gh auth token)"
export GITHUB_TOKEN

if [ ! -d .git ]; then
    log_error "Detected '$REPO_NAME' as a git submodule"
    log_error "Please run this script in a standalone '$REPO_NAME' repository"
    exit 1
fi

current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ "$current_branch" != "$DEFAULT_BRANCH" ]; then
    log_warning "You are on branch '${current_branch}', not '${DEFAULT_BRANCH}'."
    read -rp "Proceed anyway? Y to confirm: " confirm
    if [[ "$confirm" != "Y" ]]; then
        log_error "Aborted by user."
        exit 1
    fi
fi

echo "Existing tags:"
git for-each-ref --sort=-creatordate --format '- %(refname:short)' refs/tags | head -n 10
echo

default_version="$1"
# Decide prompt message based on VERSION_TAG_PREFIX_MODE
case "$VERSION_TAG_PREFIX_MODE" in
require)
    prompt_msg="Enter new version tag (must start with 'v', e.g. v1.2.3): "
    ;;
forbid)
    prompt_msg="Enter new version tag (must NOT start with 'v', e.g. 1.2.3): "
    ;;
ignore)
    prompt_msg="Enter new version tag (e.g. v1.2.3, v1.2.3-dev0): "
    ;;
*)
    log_error "Invalid VERSION_TAG_PREFIX_MODE: ${VERSION_TAG_PREFIX_MODE}. Should be require|forbid|ignore"
    exit 1
    ;;
esac

read -e -i "$default_version" -rp "$prompt_msg" version_tag

# Trim leading/trailing whitespace
version_tag=$(echo "$version_tag" | xargs)

if [ -z "$version_tag" ]; then
    log_error "No version tag provided."
    exit 1
fi

if semver valid "$version_tag" >/dev/null; then
    log_success "Valid SemVer: $version_tag"
else
    log_error "Invalid SemVer: \"$version_tag\""
    exit 1
fi

case "${VERSION_TAG_PREFIX_MODE}" in
require)
    if [[ "${version_tag}" != v* ]]; then
        log_error "Error: version_tag must start with 'v' (got: ${version_tag})"
        exit 1
    fi
    ;;
forbid)
    if [[ "${version_tag}" == v* ]]; then
        log_error "Error: version_tag must NOT start with 'v' (got: ${version_tag})"
        exit 1
    fi
    ;;
ignore | "")
    # do nothing
    ;;
    # NOTE: Invalid option is already checked during version prompt
esac

# Define your cleanup or final function
exit_message() {
    log_warning "-----------------"
    log_warning "If you aren't happy with these changes, try again with"
    log_warning "git reset --soft HEAD~1"
    log_warning "git tag -d $version_tag"
}
trap exit_message EXIT

# Determine directory of this script
SCRIPT_DIR="${SCRIPT_DIR?error}"
cd "$SCRIPT_DIR"

FUGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Preparing $version_tag..."

# ---- [START] CUSTOM HOOK ----
"$RELEASE_CUSTOM_HOOK"
# ---- [END] CUSTOM HOOK ----

# update the changelog
git-cliff "$START_COMMIT..HEAD" --config "$FUGIT_SCRIPT_DIR/../configs/cliff.toml" --tag "$version_tag" >CHANGELOG.md
git add CHANGELOG.md
git commit -m "chore(release): prepare for $version_tag"
git show

# generate a changelog for the tag message
export GIT_CLIFF_TEMPLATE="\
    {% for group, commits in commits | group_by(attribute=\"group\") %}
    {{ group | upper_first }}\
    {% for commit in commits %}
        - {% if commit.breaking %}(breaking) {% endif %}{{ commit.message | upper_first }} ({{ commit.id | truncate(length=7, end=\"\") }})\
    {% endfor %}
    {% endfor %}"
changelog=$(git-cliff "$START_COMMIT..HEAD" --config detailed.toml --unreleased --strip all)

# create a signed tag
# https://keyserver.ubuntu.com/pks/lookup?search=0x4A92FA17B6619297&op=vindex
git tag "$version_tag" -m "Release $version_tag" -m "$changelog"
git tag -v "$version_tag"
log_success "Done!"
log_success "You can now push the tag (git push origin $version_tag)"
log_success "If the github workflow works as expected, push the commit (git push) to default branch"
