#!/usr/bin/env bash

set -euo pipefail

# Set namespace to default
export HELM_NAMESPACE=${CUSTOM_HELM_NAMESPACE:-default}

FUGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_utils.sh
source "${FUGIT_SCRIPT_DIR}/_utils.sh"

check_yq
check_helm

# Determine directory of this script
TESTS_FILE="tests.yaml"
SNAPSHOT_DIR="snapshots"

SCRIPT_DIR="${SCRIPT_DIR?error}"
cd "$SCRIPT_DIR"

CHECK_DIFF_ONLY=false
DIFF_CMD="diff -u"

while [[ $# -gt 0 ]]; do
    case "$1" in

    --check-diff-only)
        CHECK_DIFF_ONLY=true
        shift
        ;;

    --diff-cmd=*)
        DIFF_CMD="${1#*=}"
        shift
        ;;

    --diff-cmd)
        shift
        DIFF_CMD=""

        # collect everything until next flag
        while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
            if [[ -n "$DIFF_CMD" ]]; then
                DIFF_CMD+=" "
            fi
            DIFF_CMD+="$1"
            shift
        done
        ;;

    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

log_warning "Using diff command ($DIFF_CMD)."

mkdir -p "$SNAPSHOT_DIR"

# Read test names
TEST_NAMES=$(yq '.tests | keys | .[]' "$TESTS_FILE")

overall_ok=true

for test_name in $TEST_NAMES; do
    log_info "=== Processing test: $test_name ==="

    VALUES_ARGS=()
    VALUES=$(yq ".tests.\"$test_name\"[]" "$TESTS_FILE")
    for values_file in $VALUES; do
        VALUES_ARGS+=(--values "$values_file")
    done
    VALUES_ARGS+=(--values "tests/$test_name")

    SNAPSHOT_PATH="${SNAPSHOT_DIR}/${test_name%.yaml}.yaml"

    # Render template to temp file
    TMP_OUTPUT=$(mktemp)
    log_warning "-> helm template ./ ${VALUES_ARGS[*]}"
    helm template ./ "${VALUES_ARGS[@]}" >"$TMP_OUTPUT"

    if $CHECK_DIFF_ONLY; then
        if [[ ! -f "$SNAPSHOT_PATH" ]]; then
            log_error "❌ Snapshot missing: $SNAPSHOT_PATH"
            overall_ok=false
            continue
        fi

        if diff -u "$SNAPSHOT_PATH" "$TMP_OUTPUT" >/dev/null; then
            log_success "✔ Snapshot up to date: $SNAPSHOT_PATH"
        else
            log_error "❌ Snapshot out of date: $SNAPSHOT_PATH"
            log_warning "--- Diff: ---"
            $DIFF_CMD "$SNAPSHOT_PATH" "$TMP_OUTPUT" || true
            overall_ok=false
        fi
    else
        # Update snapshot
        mv "$TMP_OUTPUT" "$SNAPSHOT_PATH"
        log_success "✔ Snapshot updated: $SNAPSHOT_PATH"
    fi
done

if $CHECK_DIFF_ONLY; then
    if $overall_ok; then
        log_success "✔ All snapshots are up to date."
        exit 0
    else
        log_error "❌ Some snapshots are outdated."
        exit 1
    fi
fi
