#!/usr/bin/env bash
set -euo pipefail

# run-kimchi.sh
# Invokes Kimchi in non-interactive mode to diagnose and repair failing tests.

# ── Parse arguments ────────────────────────────────────────────────────
FAILURE_LOG=""
WORKING_DIRECTORY=""
API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failure-log)
      FAILURE_LOG="$2"
      shift 2
      ;;
    --working-directory)
      WORKING_DIRECTORY="$2"
      shift 2
      ;;
    --api-key)
      API_KEY="$2"
      shift 2
      ;;
    *)
      echo "[run-kimchi] Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${FAILURE_LOG}" || -z "${WORKING_DIRECTORY}" || -z "${API_KEY}" ]]; then
  echo "[run-kimchi] Usage: $0 --failure-log <path> --working-directory <path> --api-key <key>"
  exit 1
fi

echo "[run-kimchi] Starting Kimchi self-healing agent..."

# ── 1. Pre-flight checks ─────────────────────────────────────────────

if ! command -v kimchi &>/dev/null; then
  echo "[run-kimchi] ERROR: kimchi CLI is not installed or not in PATH."
  exit 1
fi

if [[ ! -f "${FAILURE_LOG}" ]]; then
  echo "[run-kimchi] WARNING: ${FAILURE_LOG} not found. Skipping repair."
  exit 0
fi

FAILURE_CONTENT="$(cat "${FAILURE_LOG}")"

# ── 2. Safety guards ─────────────────────────────────────────────────

CRITICAL_PATHS=(".github/workflows" ".git")
for p in "${CRITICAL_PATHS[@]}"; do
  if [[ -d "${WORKING_DIRECTORY}/${p}" ]]; then
    chmod -R a-w "${WORKING_DIRECTORY}/${p}"
  fi
done

cleanup_safety() {
  for p in "${CRITICAL_PATHS[@]}"; do
    if [[ -d "${WORKING_DIRECTORY}/${p}" ]]; then
      chmod -R u+w "${WORKING_DIRECTORY}/${p}" 2>/dev/null || true
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
4. Run the test command again to confirm the fix.
5. If tests pass, stop. If they still fail, investigate again and retry.

## Safety Rules (MANDATORY)
- Do NOT delete repository history.
- Do NOT force push.
- Do NOT modify files in .github/workflows/.
- Do NOT disable, skip, or remove any tests.
- Do NOT remove assertions simply to make tests pass.
- Do NOT modify unrelated files.
- Preserve existing code style and comments.
- Only modify source files, not test files.

## Repository Layout
- ./src/     : application source code (you may edit)
- ./tests/   : test files (read-only; do not edit)
PROMPT
)"

# ── 4. Attempt headless or fallback to --print ───────────────────────

HEADLESS_SUCCESS=false

if kimchi --help 2>&1 | grep -q -- '--headless'; then
  echo "[run-kimchi] Detected --headless support. Creating Ferment JSON..."
  if command -v python3 &>/dev/null; then
    KIMCHI_DIR="${WORKING_DIRECTORY}/.kimchi"
    FERMENTS_DIR="${KIMCHI_DIR}/ferments"
    mkdir -p "${FERMENTS_DIR}"
    FERMENT_ID=""
    if command -v uuidgen &>/dev/null; then
      FERMENT_ID="$(uuidgen)"
    else
      FERMENT_ID="$(python3 -c "import uuid; print(uuid.uuid4())")"
    fi
    FERMENT_FILE="${FERMENTS_DIR}/${FERMENT_ID}.json"
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 -c "
import json, sys
ferment = {
    'id': '${FERMENT_ID}',
    'name': 'Auto-Fix CI Failure',
    'description': sys.stdin.read(),
    'status': 'draft',
    'worktree': {'path': '${WORKING_DIRECTORY}'},
    'scoping': {},
    'phases': [],
    'decisions': [],
    'memories': [],
    'createdAt': '${TIMESTAMP}',
    'updatedAt': '${TIMESTAMP}'
}
print(json.dumps(ferment, indent=2))
" > "${FERMENT_FILE}" <<< "${TASK_PROMPT}"
    export KIMCHI_ACTIVE_FERMENT="${FERMENT_ID}"
    export KIMCHI_API_KEY="${API_KEY}"
    if (
      cd "${WORKING_DIRECTORY}"
      kimchi --headless
    ); then
      HEADLESS_SUCCESS=true
      echo "[run-kimchi] Headless execution completed."
    else
      echo "[run-kimchi] WARNING: Headless mode exited with an error. Falling back to --print."
    fi
  else
    echo "[run-kimchi] Python3 unavailable; cannot safely generate Ferment JSON. Using --print fallback."
  fi
else
  echo "[run-kimchi] --headless not detected. Using --print fallback."
fi

if [[ "${HEADLESS_SUCCESS}" == "false" ]]; then
  echo "[run-kimchi] Launching Kimchi in print (non-interactive) mode..."
  (
    cd "${WORKING_DIRECTORY}"
    KIMCHI_API_KEY="${API_KEY}" kimchi -p "${TASK_PROMPT}"
  )
fi

# ── 5. Validate that changes were made ───────────────────────────────

echo "[run-kimchi] Checking for code changes..."
if git -C "${WORKING_DIRECTORY}" diff --quiet; then
  echo "[run-kimchi] No changes were made by Kimchi."
  exit 0
else
  echo "[run-kimchi] Changes detected in the working tree."
  git -C "${WORKING_DIRECTORY}" diff --stat
  exit 0
fi
