#!/usr/bin/env bash
# Common setup for all bats test suites.

# Load helper libraries when they exist.
# These are installed by CI or cloned manually into tests/test_helper/.
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}"

helpers=(
  "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load.bash"
  "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load.bash"
  "${BATS_TEST_DIRNAME}/../test_helper/bats-file/load.bash"
)

for helper in "${helpers[@]}"; do
  if [[ -f "$helper" ]]; then
    # shellcheck source=/dev/null
    source "$helper"
  fi
done

# Resolve project root relative to this file.
export PROJECT_ROOT
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# Add scripts directory to PATH for convenience.
export PATH="${PROJECT_ROOT}/scripts:${PATH}"
