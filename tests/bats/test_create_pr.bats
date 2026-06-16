#!/usr/bin/env bats

# Test create-pr.sh with mocked git and gh via PATH stubs.

setup() {
  # Source common helpers when available.
  if [[ -f "${BATS_TEST_DIRNAME}/../test_helper/common_setup.bash" ]]; then
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../test_helper/common_setup.bash"
  else
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PATH="${PROJECT_ROOT}/scripts:${PATH}"
  fi

  # Create an isolated temp workspace for each test.
  TEST_DIR="$(mktemp -d)"
  export TEST_DIR

  # Build mock binary directory.
  MOCK_BIN="${TEST_DIR}/mock_bin"
  mkdir -p "${MOCK_BIN}"
  export MOCK_BIN

  # Prepend mock binaries to PATH so they shadow the real git/gh.
  export PATH="${MOCK_BIN}:${PATH}"

  # Record mock invocation traces in files.
  export GIT_TRACE="${TEST_DIR}/git_trace.txt"
  export GH_TRACE="${TEST_DIR}/gh_trace.txt"
  export GH_PR_URL="https://github.com/test-org/test-repo/pull/42"

  # Provide a fake GITHUB_TOKEN to get past the early env checks.
  export GITHUB_TOKEN="fake_token"
}

teardown() {
  if [[ -n "${TEST_DIR:-}" && -d "${TEST_DIR}" ]]; then
    rm -rf "${TEST_DIR}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════

write_mock_git_changes() {
  cat > "${MOCK_BIN}/git" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "$@" >> "${GIT_TRACE}"

# Simulate `git -C <dir> diff --quiet` and `diff --cached --quiet`
if [[ "$*" == *"diff --quiet"* ]]; then
  # Non-zero exit means there ARE changes.
  exit 1
fi

# Simulate `git branch --show-current`
if [[ "$*" == *"branch --show-current"* ]]; then
  echo "main"
  exit 0
fi

# Simulate `git diff --name-only`
if [[ "$*" == *"diff --name-only"* ]]; then
  echo "demo-app/src/calculator.ts"
  exit 0
fi

# Simulate `git config user.name` and `git config user.email`
if [[ "$*" == *"config user.name"* ]] || [[ "$*" == *"config user.email"* ]]; then
  echo ""
  exit 0
fi

# All other git commands succeed silently.
exit 0
MOCK_EOF
  chmod +x "${MOCK_BIN}/git"
}

write_mock_git_no_changes() {
  cat > "${MOCK_BIN}/git" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "$@" >> "${GIT_TRACE}"

if [[ "$*" == *"diff --quiet"* ]]; then
  # Zero exit means NO changes.
  exit 0
fi

exit 0
MOCK_EOF
  chmod +x "${MOCK_BIN}/git"
}

write_mock_gh() {
  cat > "${MOCK_BIN}/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
echo "$@" >> "${GH_TRACE}"

if [[ "$1" == "pr" && "$2" == "create" ]]; then
  echo "${GH_PR_URL}"
  exit 0
fi

exit 0
MOCK_EOF
  chmod +x "${MOCK_BIN}/gh"
}

# ═══════════════════════════════════════════════════════════════════════
# Tests
# ═══════════════════════════════════════════════════════════════════════

@test "create-pr exits 0 when no changes exist" {
  write_mock_git_no_changes
  write_mock_gh

  run bash "${PROJECT_ROOT}/scripts/create-pr.sh"
  assert [ "$status" -eq 0 ]
  assert_output --partial "No uncommitted changes found"

  # gh pr create should NOT have been called.
  assert [ ! -f "${GH_TRACE}" ]
}

@test "create-pr creates branch, commits, and opens PR when changes exist" {
  write_mock_git_changes
  write_mock_gh

  run bash "${PROJECT_ROOT}/scripts/create-pr.sh"
  assert [ "$status" -eq 0 ]
  assert_output --partial "Pull Request created successfully"

  # Verify git commands were invoked.
  assert [ -f "${GIT_TRACE}" ]
  grep -q "diff --quiet" "${GIT_TRACE}"
  grep -q "branch --show-current" "${GIT_TRACE}"
  grep -q "checkout -b" "${GIT_TRACE}"
  grep -q "add -A" "${GIT_TRACE}"
  grep -q "push origin" "${GIT_TRACE}"

  # Verify gh pr create was called.
  assert [ -f "${GH_TRACE}" ]
  grep -q -e "pr create" "${GH_TRACE}"
  grep -q -e "--title" "${GH_TRACE}"
  grep -q -e "--base" "${GH_TRACE}"
}

@test "create-pr includes PR title and base branch in gh invocation" {
  write_mock_git_changes
  write_mock_gh

  run bash "${PROJECT_ROOT}/scripts/create-pr.sh"
  assert [ "$status" -eq 0 ]

  assert [ -f "${GH_TRACE}" ]
  grep -q -e "\[Kimchi Auto-Fix\] Resolve failing CI pipeline" "${GH_TRACE}"
  grep -q -e "--base main" "${GH_TRACE}"
}
