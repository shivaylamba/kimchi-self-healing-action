#!/usr/bin/env bash
set -euo pipefail

# run-kimchi.sh
# Invokes Kimchi in a non-interactive mode to diagnose and repair failing
# tests. The script attempts the preferred Ferment headless route
# (KIMCHI_ACTIVE_FERMENT + kimchi --headless) whenever possible and
# falls back to kimchi --print if headless mode is unavailable.

# Repository root derived from script location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Configuration (override via environment).
FAILURE_LOG="${FAILURE_LOG:-${REPO_ROOT}/failure.log}"
KIMCHI_DIR="${KIMCHI_DIR:-${REPO_ROOT}/.kimchi}"
SOURCE_DIR="${SOURCE_DIR:-${REPO_ROOT}}"
ALLOWED_PATHS="${ALLOWED_PATHS:-}"
BLOCKED_PATHS="${BLOCKED_PATHS:-}"
JOB_TIMEOUT="${JOB_TIMEOUT:-300}"

echo "[run-kimchi] Starting Kimchi self-healing agent..."

# ── 1. Pre-flight checks ─────────────────────────────────────────────

if [[ -z "${KIMCHI_API_KEY:-}" ]]; then
  echo "[run-kimchi] ERROR: KIMCHI_API_KEY environment variable is not set."
  echo "[run-kimchi] Add it as a GitHub repository secret (Settings → Secrets and variables → Actions)."
  exit 1
fi

if ! command -v kimchi &>/dev/null; then
  echo "[run-kimchi] ERROR: kimchi CLI is not installed or not in PATH."
  echo "[run-kimchi] Install instructions: https://docs.kimchi.dev"
  exit 1
fi

if [[ ! -f "${FAILURE_LOG}" ]]; then
  echo "[run-kimchi] WARNING: ${FAILURE_LOG} not found. Skipping repair."
  exit 0
fi

FAILURE_CONTENT="$(cat "${FAILURE_LOG}")"

# ── 2. Safety guards ─────────────────────────────────────────────────

# Protect critical paths from modification while Kimchi is running.
# Permissions are restored via the EXIT trap.
CRITICAL_PATHS=(".github/workflows" ".git")
for p in "${CRITICAL_PATHS[@]}"; do
  if [[ -d "${REPO_ROOT}/${p}" ]]; then
    chmod -R a-w "${REPO_ROOT}/${p}"
  fi
done

# shellcheck disable=SC2317
cleanup_safety() {
  for p in "${CRITICAL_PATHS[@]}"; do
    if [[ -d "${REPO_ROOT}/${p}" ]]; then
      chmod -R u+w "${REPO_ROOT}/${p}" 2>/dev/null || true
    fi
  done
}
trap cleanup_safety EXIT

# ── 3. Construct the task prompt ─────────────────────────────────────

TASK_PROMPT=$(cat <<'PROMPT'
You are an autonomous coding agent running inside a GitHub Actions CI pipeline.

## Failure Log
The test suite failed with the following output:

PROMPT
)

TASK_PROMPT="${TASK_PROMPT}${FAILURE_CONTENT}"

TASK_PROMPT="${TASK_PROMPT}$(cat <<'PROMPT'

## Your Task
1. Read the failure log carefully and identify which test is failing.
2. Investigate the source code to find the root cause.
3. Make the MINIMAL possible code change to fix the bug.
4. Re-run the test suite to confirm the fix.
5. If tests pass, stop. If they still fail, investigate again and retry.

## Safety Rules (MANDATORY)
- Do NOT delete repository history.
- Do NOT force push.
- Do NOT modify files in .github/workflows/.
- Do NOT disable, skip, or remove any tests.
- Do NOT remove assertions simply to make tests pass.
- Do NOT modify unrelated files.
- Preserve existing code style and comments.
- Only modify source files in the configured source directory.
PROMPT
)"

# ── 4. Attempt headless Ferment mode ─────────────────────────────────

HEADLESS_SUCCESS=false

if kimchi --help 2>&1 | grep -q -- '--headless'; then
  echo "[run-kimchi] Detected --headless support. Creating Ferment JSON..."

  # Ensure Python is available for safe JSON generation.
  if command -v python3 &>/dev/null; then
    mkdir -p "${KIMCHI_DIR}/ferments"

    FERMENTS_DIR="${KIMCHI_DIR}/ferments"

    # Generate a UUID for this fermentation run.
    FERMENT_ID=""
    if command -v uuidgen &>/dev/null; then
      FERMENT_ID="$(uuidgen)"
    else
      FERMENT_ID="$(python3 -c "import uuid; print(uuid.uuid4())")"
    fi

    FERMENT_FILE="${FERMENTS_DIR}/${FERMENT_ID}.json"

    # Generate valid JSON safely with environment variables.
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    export FERMENT_ID REPO_ROOT TIMESTAMP
    python3 -c '
import json, sys, os
ferment_id = os.environ["FERMENT_ID"]
repo_root = os.environ["REPO_ROOT"]
timestamp = os.environ["TIMESTAMP"]
prompt = sys.stdin.read()
ferment = {
    "id": ferment_id,
    "name": "Auto-Fix CI Failure",
    "description": prompt,
    "status": "draft",
    "worktree": {"path": repo_root},
    "scoping": {},
    "phases": [],
    "decisions": [],
    "memories": [],
    "createdAt": timestamp,
    "updatedAt": timestamp
}
print(json.dumps(ferment, indent=2))
' > "${FERMENT_FILE}" <<< "${TASK_PROMPT}"

    export KIMCHI_ACTIVE_FERMENT="${FERMENT_ID}"
    echo "[run-kimchi] Launching Kimchi headless with ferment ${FERMENT_ID}..."

    if (
      cd "${REPO_ROOT}"
      kimchi --headless
    ); then
      HEADLESS_SUCCESS=true
      echo "[run-kimchi] Headless execution completed."
    else
      echo "[run-kimchi] WARNING: Headless mode exited with an error. Falling back to --print."
    fi
  else
    echo "[run-kimchi] Python3 is unavailable; cannot safely generate Ferment JSON. Using --print fallback."
  fi
else
  echo "[run-kimchi] --headless not detected in kimchi CLI. Using --print fallback."
fi

# ── 5. Fallback to --print mode ──────────────────────────────────────

if [[ "${HEADLESS_SUCCESS}" == "false" ]]; then
  echo "[run-kimchi] Launching Kimchi in print (non-interactive) mode..."
  (
    cd "${REPO_ROOT}"
    kimchi -p "${TASK_PROMPT}"
  )
fi

# ── 6. Validate that changes were made ───────────────────────────────

echo "[run-kimchi] Checking for code changes..."

if git -C "${REPO_ROOT}" diff --quiet; then
  echo "[run-kimchi] No changes were made by Kimchi."
  exit 0
else
  echo "[run-kimchi] Changes detected in the working tree."
  git -C "${REPO_ROOT}" diff --stat
  exit 0
fi
