#!/usr/bin/env bash
set -euo pipefail

# collect-failure.sh
# Runs the configured test suite and captures both the output and the exact
# exit code. The exit code is saved to <failure.log>.exitcode so downstream
# steps can use the real numeric exit status instead of grepping logs.

# Repository root derived from script location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Configuration (override via environment).
TEST_CMD="${TEST_CMD:-}"
SOURCE_DIR="${SOURCE_DIR:-${REPO_ROOT}}"
FAILURE_LOG="${FAILURE_LOG:-${REPO_ROOT}/failure.log}"

if [[ -z "${TEST_CMD}" ]]; then
  echo "[collect-failure] ERROR: TEST_CMD environment variable is not set."
  exit 1
fi

echo "[collect-failure] Running tests: ${TEST_CMD} ..."

# Clear any prior log and exit-code file.
: > "${FAILURE_LOG}"
rm -f "${FAILURE_LOG}.exitcode"

TEST_EXIT_CODE=0

if cd "${SOURCE_DIR}"; then
  # Disable errexit and pipefail around the test command so we can capture
  # its real exit code even when it fails.
  set +eo pipefail
  # shellcheck disable=SC2086
  eval "${TEST_CMD}" >"${FAILURE_LOG}" 2>&1
  TEST_EXIT_CODE=$?
  set -euo pipefail
else
  echo "[collect-failure] ERROR: Could not enter ${SOURCE_DIR}" >"${FAILURE_LOG}"
  TEST_EXIT_CODE=1
fi

# Mirror the captured output to stdout for CI log visibility.
cat "${FAILURE_LOG}"

# Persist the real exit code for downstream validation steps.
echo "${TEST_EXIT_CODE}" >"${FAILURE_LOG}.exitcode"

if [[ "${TEST_EXIT_CODE}" -eq 0 ]]; then
  echo "[collect-failure] Tests passed (exit code 0). No failure log needed."
else
  echo "[collect-failure] Tests failed with exit code ${TEST_EXIT_CODE}."
  echo "[collect-failure] Output saved to ${FAILURE_LOG}"
  echo "[collect-failure] Exit code saved to ${FAILURE_LOG}.exitcode"
fi

# Always exit 0 so the workflow continues to the self-healing phase.
exit 0
