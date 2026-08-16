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
TEST_NAMES=()
while IFS= read -r test_name; do
    [[ -n "$test_name" ]] && TEST_NAMES+=("$test_name")
done < <(yq '.tests | keys | .[]' "$TESTS_FILE")

overall_ok=true

# A test key names its snapshot only; every values file comes from its list. Two keys
# differing just by the .yaml suffix would overwrite each other, so reject them before
# rendering anything.
declare -A SNAPSHOT_OWNERS=()
for test_name in ${TEST_NAMES[@]+"${TEST_NAMES[@]}"}; do
    SNAPSHOT_NAME="${test_name%.yaml}"
    if [[ -n "${SNAPSHOT_OWNERS[$SNAPSHOT_NAME]:-}" ]]; then
        log_error "❌ Tests '${SNAPSHOT_OWNERS[$SNAPSHOT_NAME]}' and '$test_name' both write ${SNAPSHOT_DIR}/${SNAPSHOT_NAME}.yaml"
        log_error "   Test keys must resolve to distinct snapshot names ('<name>' and '<name>.yaml' collide)."
        exit 1
    fi
    SNAPSHOT_OWNERS[$SNAPSHOT_NAME]="$test_name"
done

for test_name in ${TEST_NAMES[@]+"${TEST_NAMES[@]}"}; do
    log_info "=== Processing test: $test_name ==="

    SNAPSHOT_PATH="${SNAPSHOT_DIR}/${test_name%.yaml}.yaml"

    VALUES_FILES=()
    while IFS= read -r values_file; do
        [[ -n "$values_file" ]] && VALUES_FILES+=("$values_file")
    done < <(yq ".tests.\"$test_name\"[]" "$TESTS_FILE")

    # tests/<key> used to be appended automatically. It now has to be listed like
    # any other file, so fail loudly instead of silently dropping it from a render.
    DEFAULT_VALUES="tests/$test_name"
    if [[ -f "$DEFAULT_VALUES" ]]; then
        default_values_listed=false
        for values_file in ${VALUES_FILES[@]+"${VALUES_FILES[@]}"}; do
            if [[ "$values_file" == "$DEFAULT_VALUES" ]]; then
                default_values_listed=true
                break
            fi
        done
        if ! $default_values_listed; then
            log_error "❌ $DEFAULT_VALUES exists but is not listed under tests.\"$test_name\" in $TESTS_FILE"
            log_error "   Auto-inclusion of tests/<key> was removed: add it to the list (order matters) or delete the file."
            exit 1
        fi
    fi

    VALUES_ARGS=()
    for values_file in ${VALUES_FILES[@]+"${VALUES_FILES[@]}"}; do
        VALUES_ARGS+=(--values "$values_file")
    done

    # Render template to temp file
    TMP_OUTPUT=$(mktemp)
    log_warning "-> helm template ./ ${VALUES_ARGS[*]-}"
    helm template ./ ${VALUES_ARGS[@]+"${VALUES_ARGS[@]}"} >"$TMP_OUTPUT"

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
