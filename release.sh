#!/bin/bash

export SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function release_custom_hook {
    echo ""
}

export -f release_custom_hook
export START_COMMIT=dff33ca23fa3311c00d5ecca5adacc1e260614c1
export RELEASE_CUSTOM_HOOK=release_custom_hook
export REPO_NAME=toggle-corp/fugit
export DEFAULT_BRANCH=main

export GIT_CLIFF__REMOTE__GITHUB__OWNER=toggle-corp
export GIT_CLIFF__REMOTE__GITHUB__REPO=fugit

$SCRIPT_DIR/scripts/release.sh
