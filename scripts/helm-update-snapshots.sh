#!/bin/bash

set -euo pipefail

FUGIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${FUGIT_SCRIPT_DIR}/_utils.sh"

check_yq
check_helm

# Determine directory of this script
TESTS_FILE="tests.yaml"
SNAPSHOT_DIR="snapshots"

SCRIPT_DIR="${SCRIPT_DIR?error}"
cd "$SCRIPT_DIR"

CHECK_DIFF_ONLY=false
# Parse command line flags
for arg in "$@"; do
    case "$arg" in
        --check-diff-only)
            log_warning "Running in diff-only mode (no snapshot updates)."
            CHECK_DIFF_ONLY=true
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Usage: $0 [--check-diff-only]"
            exit 1
            ;;
    esac
done

mkdir -p "$SNAPSHOT_DIR"

# Read test names
TEST_NAMES=$(yq '.tests | keys | .[]' "$TESTS_FILE")

overall_ok=true

for test_name in $TEST_NAMES; do
    log_warning "Processing test: $test_name"

    VALUES_ARGS=()
    VALUES=$(yq ".tests.\"$test_name\"[]" "$TESTS_FILE")
    for values_file in $VALUES; do
        VALUES_ARGS+=( --values "$values_file" )
    done
    VALUES_ARGS+=( --values "tests/$test_name" )

    SNAPSHOT_PATH="${SNAPSHOT_DIR}/${test_name%.yaml}.yaml"

    # Render template to temp file
    TMP_OUTPUT=$(mktemp)
    helm template ./ "${VALUES_ARGS[@]}" > "$TMP_OUTPUT"

    if $CHECK_DIFF_ONLY; then
        if [[ ! -f "$SNAPSHOT_PATH" ]]; then
            log_error "❌ Snapshot missing: $SNAPSHOT_PATH"
            overall_ok=false
            continue
        fi

        if diff -u "$SNAPSHOT_PATH" "$TMP_OUTPUT" > /dev/null; then
            log_success "✔ Snapshot up to date: $SNAPSHOT_PATH"
        else
            log_error "❌ Snapshot out of date: $SNAPSHOT_PATH"
            log_warning "--- Diff: ---"
            diff -u "$SNAPSHOT_PATH" "$TMP_OUTPUT" || true
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
