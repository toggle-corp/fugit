#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Configuration
# -------------------------------
DEFAULT_BRANCH="main"

# -------------------------------
# Colors & formatting (auto-disable if not TTY)
# -------------------------------
if [[ -t 1 ]]; then
    RED="$(tput setaf 1)"
    YELLOW="$(tput setaf 3)"
    GREEN="$(tput setaf 2)"
    BLUE="$(tput setaf 4)"
    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"
else
    RED=""
    YELLOW=""
    GREEN=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# -------------------------------
# Logging functions (centralized, bold + color + emoji)
# -------------------------------
log_info() { printf "${BLUE}ℹ️  ${BOLD}%s${RESET}\n" "$*"; }
log_success() { printf "${GREEN}✅ ${BOLD}%s${RESET}\n" "$*"; }
log_warning() { printf "${YELLOW}⚠️  ${BOLD}%s${RESET}\n" "$*" >&2; }
log_error() {
    printf "${RED}❌ ${BOLD}%s${RESET}\n" "$*" >&2
}
echo_border() {
    echo -e "${BLUE}----------------------------------------${RESET}"
}

# -------------------------------
# Submodule update function
# -------------------------------
update_submodule() {
    local name="${name:-}"
    local toplevel="${toplevel:-}"

    : "${name:?missing submodule name}"
    : "${toplevel:?missing toplevel}"

    # pretty aligned submodule name
    echo -e "\n${YELLOW}-> 🗂️ $name  ${RESET}"

    # Fetch
    if git fetch --all --prune >/dev/null 2>&1; then
        log_success "fetch"
    else
        log_error "fetch (failed)"
        return
    fi

    # Determine branch
    local branch
    branch="$(git config -f "$toplevel/.gitmodules" "submodule.$name.branch" 2>/dev/null || true)"
    branch="${branch:-$DEFAULT_BRANCH}"

    # Checkout branch
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        if git checkout "$branch"; then
            log_success "branch $branch"
        else
            log_error "branch $branch (checkout failed)"
        fi
    elif git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        if git checkout -b "$branch" "origin/$branch"; then
            log_success "branch $branch"
        else
            log_error "branch $branch (checkout failed)"
        fi
    elif git show-ref --verify --quiet "refs/tags/$branch"; then
        if git checkout "$branch"; then
            log_success "tag $branch"
        else
            log_error "tag $branch (checkout failed)"
        fi
    elif git ls-remote --exit-code --tags origin "$branch" >/dev/null 2>&1; then
        git fetch origin "refs/tags/$branch:refs/tags/$branch"
        if git checkout "$branch"; then
            log_success "tag $branch"
        else
            log_error "tag $branch (checkout failed)"
        fi
    else
        log_error "branch/tag $branch (not found)"
    fi
}

# -------------------------------
# Export functions & variables
# -------------------------------
export -f update_submodule
export -f log_info log_warning log_error log_success echo_border
export RED YELLOW GREEN BLUE BOLD RESET
export DEFAULT_BRANCH

# -------------------------------
# Main flow
# -------------------------------
log_info "Processing repository: $(pwd)"

read -r -p "Proceed? [y/N]: " confirm
confirm="${confirm:-N}"

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warning "Aborted by user"
    exit 0
fi

log_info "Updating submodules..."

git submodule foreach --quiet 'bash -c update_submodule'
