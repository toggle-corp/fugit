#!/bin/bash

set -euo pipefail

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

FUGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUGIT_ROOT_DIR=$(realpath "$FUGIT_SCRIPT_DIR/../")
export FUGIT_ROOT_DIR

# Logger helper
function log_success() {
    echo -e "${GREEN}$1${RESET}"
}

function log_error() {
    echo -e "${RED}$1${RESET}"
}

function log_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

# Command check helper
function check_typos {
    if ! command -v typos &>/dev/null; then
        log_error "typos is not installed."
        log_error "Run 'cargo install typos-cli' to install it, otherwise the typos won't be fixed"
        exit 1
    fi
}

function check_git_cliff {
    if ! command -v git-cliff &>/dev/null; then
        log_error "git-cliff is not installed."
        log_error "Follow the instruction from https://git-cliff.org/docs/installation/"
        exit 1
    fi
}

function check_semver {
    if ! command -v semver &>/dev/null; then
        log_error "semver is required to validate the tag."
        exit 1
    fi
}

function check_gh {
    if ! command -v gh &>/dev/null; then
        log_error "gh is required to generate GITHUB_TOKEN."
        exit 1
    fi
}

function check_yq {
    if ! command -v yq &>/dev/null; then
        log_error "yq is required to parse yaml ."
        exit 1
    fi
    # Also validate that yq is the new one (go based) instead of old one (python based)
    # OLD: https://github.com/kislyuk/yq
    if ! yq eval '.' <<<'{}' >/dev/null 2>&1; then
        log_error "You are using old python based yq. Please install the new one: https://github.com/mikefarah/yq"
        echo "For arch: sudo pacman -S go-yq"
        exit
    fi
}

function check_helm {
    if ! command -v helm &>/dev/null; then
        log_error "helm is required to process helm charts ."
        exit 1
    fi
}
