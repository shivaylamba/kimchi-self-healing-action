#!/usr/bin/env bats

# Test validate-paths.sh with simulated git state and PATH stubs.

setup() {
  if [[ -f "${BATS_TEST_DIRNAME}/../test_helper/common_setup.bash" ]]; then
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../test_helper/common_setup.bash"
  else
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PATH="${PROJECT_ROOT}/scripts:${PATH}"
  fi

  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  # Create a fake git repo inside TEST_DIR.
  mkdir -p "${TEST_DIR}/.git"
  export GIT_TRACE="${TEST_DIR}/git_trace.txt"

  # Build mock git binary.
  MOCK_BIN="${TEST_DIR}/mock_bin"
  mkdir -p "${MOCK_BIN}"

  export PATH="${MOCK_BIN}:${PATH}"

  # Provide a fake GITHUB_OUTPUT file for the script to write to.
  export GITHUB_OUTPUT="${TEST_DIR}/github_output.txt"
  : >"${GITHUB_OUTPUT}"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════

write_mock_git_diff() {
  # $1 = newline-separated list of changed file names
  local files="$1"
  cat > "${MOCK_BIN}/git" <<GIT_EOF
#!/usr/bin/env bash
echo "\$@" >> "${GIT_TRACE}"
if [[ "\$*" == *"diff --name-only"* ]]; then
$(printf '%s\n' "${files}" | sed 's/^/echo "/; s/$/"/')
  exit 0
fi
if [[ "\$*" == *"diff HEAD --"* ]]; then
  # Simulate diff output for specific files.
  for f in ${files}; do
    echo "diff --git a/\$f b/\$f"
    echo "@@ -1 +1 @@"
    echo "-old"
    echo "+new"
  done
  exit 0
fi
exit 0
GIT_EOF
  chmod +x "${MOCK_BIN}/git"
}

# ═══════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════

@test "validate-paths passes when no changes exist" {
  write_mock_git_diff ""

  run bash "${PROJECT_ROOT}/scripts/validate-paths.sh"
  assert [ "$status" -eq 0 ]
  assert_output --partial "No changes detected"

  # GITHUB_OUTPUT should contain fix-applied=false.
  assert [ -f "${GITHUB_OUTPUT}" ]
  grep -q -e "fix-applied=false" "${GITHUB_OUTPUT}"
}

@test "validate-paths blocks changes to workflow files" {
  write_mock_git_diff ".github/workflows/ci.yml"

  export BLOCKED_PATHS=".github/workflows/**"
  run bash "${PROJECT_ROOT}/scripts/validate-paths.sh"
  assert [ "$status" -eq 1 ]
  assert_output --partial "BLOCKED PATH VIOLATION DETECTED"

  # GITHUB_OUTPUT should contain the failure markers.
  grep -q -e "fix-applied=false" "${GITHUB_OUTPUT}"
  grep -q -e "validation-passed=false" "${GITHUB_OUTPUT}"
}

@test "validate-paths blocks changes to test files" {
  write_mock_git_diff "tests/calculator.test.ts"

  export BLOCKED_PATHS="tests/**"
  run bash "${PROJECT_ROOT}/scripts/validate-paths.sh"
  assert [ "$status" -eq 1 ]
  assert_output --partial "BLOCKED PATH VIOLATION DETECTED"
}

@test "validate-paths allows changes to source files" {
  write_mock_git_diff "demo-app/src/calculator.ts"

  export BLOCKED_PATHS=".github/workflows/**,tests/**"
  export ALLOWED_PATHS="demo-app/**"
  run bash "${PROJECT_ROOT}/scripts/validate-paths.sh"
  assert [ "$status" -eq 0 ]
  assert_output --partial "Safety checks passed"

  grep -q -e "fix-applied=true" "${GITHUB_OUTPUT}"
}

@test "validate-paths rejects source changes when allowlist is strict" {
  write_mock_git_diff "demo-app/src/calculator.ts"

  export BLOCKED_PATHS=".github/workflows/**,tests/**"
  export ALLOWED_PATHS="src/**"
  run bash "${PROJECT_ROOT}/scripts/validate-paths.sh"
  assert [ "$status" -eq 1 ]
  assert_output --partial "ALLOWED PATH VIOLATION DETECTED"

  grep -q -e "fix-applied=false" "${GITHUB_OUTPUT}"
}
