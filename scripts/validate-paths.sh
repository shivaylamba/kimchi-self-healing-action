#!/usr/bin/env bash
set -euo pipefail

# validate-paths.sh
# Compares git diff paths against blocked and allowed path lists.
# Prints rejected diffs to stderr and exits 1 on violation.
# Sets GITHUB_OUTPUT variables (fix-applied, validation-passed).

# Repository root derived from script location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Configuration (override via environment).
BLOCKED_PATHS="${BLOCKED_PATHS:-}"
ALLOWED_PATHS="${ALLOWED_PATHS:-}"

echo "[validate-paths] Checking modified files against safety boundaries..."

# Gather changed files.
CHANGED_FILES=""
if [[ -d "${REPO_ROOT}/.git" ]]; then
  CHANGED_FILES="$(git -C "${REPO_ROOT}" diff --name-only HEAD || true)"
fi

if [[ -z "${CHANGED_FILES}" ]]; then
  echo "[validate-paths] No changes detected."
  echo "fix-applied=false" >> "$GITHUB_OUTPUT"
  echo "validation-passed=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "[validate-paths] Changed files:"
echo "${CHANGED_FILES}"

# ── Helper: convert a glob pattern to a regex ────────────────────────
glob_to_regex() {
  local glob_pattern="$1"
  # Escape regex metacharacters except * and ?
  local regex="${glob_pattern//./\.}"
  regex="${regex//+/\+}"
  regex="${regex//\[/\[}"
  regex="${regex//\]/\]}"
  regex="${regex//(/\(}"
  regex="${regex//)/\)}"
  regex="${regex//^/\^}"
  regex="${regex//\$/\$}"
  # Handle ** (match across directories) before single *
  regex="${regex//\*\*/___DS___}"
  regex="${regex//\*/[^/]*}"
  # ** matches any characters including /
  regex="${regex//___DS___/.*}"
  # Handle single-character wildcard
  regex="${regex//\?/.}"
  echo "^${regex}$"
}

# ── Check blocked paths ──────────────────────────────────────────────
check_blocked() {
  if [[ -z "${BLOCKED_PATHS}" ]]; then
    return 0
  fi

  echo "[validate-paths] Checking blocked paths..."

  local violations=""
  IFS=',' read -ra BLOCKED_ARRAY <<< "$BLOCKED_PATHS"
  for raw_pattern in "${BLOCKED_ARRAY[@]}"; do
    local pattern
    pattern="$(echo "$raw_pattern" | xargs)"
    if [[ -z "$pattern" ]]; then
      continue
    fi

    local regex
    regex="$(glob_to_regex "$pattern")"

    while IFS= read -r file; do
      if [[ "$file" =~ $regex ]]; then
        violations="${violations}${file}\n"
      fi
    done <<< "$CHANGED_FILES"
  done

  if [[ -n "$violations" ]]; then
    echo "" >&2
    echo "========================================" >&2
    echo "BLOCKED PATH VIOLATION DETECTED" >&2
    echo "========================================" >&2
    echo -e "$violations" | while IFS= read -r vfile; do
      echo "  - ${vfile}" >&2
    done
    echo "" >&2
    echo "Rejected diff:" >&2
    echo "----------------------------------------" >&2
    while IFS= read -r vfile; do
      git -C "${REPO_ROOT}" diff HEAD -- "$vfile" >&2 || true
      echo "" >&2
    done <<< "$(echo -e "$violations" | sort -u)"
    echo "----------------------------------------" >&2
    echo "[validate-paths] ERROR: Blocked path(s) were modified. Rejecting changes." >&2
    echo "fix-applied=false" >> "$GITHUB_OUTPUT"
    echo "validation-passed=false" >> "$GITHUB_OUTPUT"
    return 1
  fi

  echo "[validate-paths] No blocked path violations."
  return 0
}

# ── Check allowed paths ─────────────────────────────────────────────
check_allowed() {
  if [[ -z "${ALLOWED_PATHS}" ]]; then
    return 0
  fi

  echo "[validate-paths] Checking allowed paths..."

  local allowed_patterns=()
  IFS=',' read -ra allowed_raw <<< "$ALLOWED_PATHS"
  for raw in "${allowed_raw[@]}"; do
    local pattern
    pattern="$(echo "$raw" | xargs)"
    if [[ -n "$pattern" ]]; then
      allowed_patterns+=("$pattern")
    fi
  done

  local violations=""
  while IFS= read -r file; do
    local matched=0
    for pattern in "${allowed_patterns[@]}"; do
      local regex
      regex="$(glob_to_regex "$pattern")"
      if [[ "$file" =~ $regex ]]; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -eq 0 ]]; then
      violations="${violations}${file}\n"
    fi
  done <<< "$CHANGED_FILES"

  if [[ -n "$violations" ]]; then
    echo "" >&2
    echo "========================================" >&2
    echo "ALLOWED PATH VIOLATION DETECTED" >&2
    echo "========================================" >&2
    echo -e "$violations" | while IFS= read -r vfile; do
      echo "  - ${vfile}" >&2
    done
    echo "" >&2
    echo "Rejected diff:" >&2
    echo "----------------------------------------" >&2
    while IFS= read -r vfile; do
      git -C "${REPO_ROOT}" diff HEAD -- "$vfile" >&2 || true
      echo "" >&2
    done <<< "$(echo -e "$violations" | sort -u)"
    echo "----------------------------------------" >&2
    echo "[validate-paths] ERROR: File(s) outside allowed paths were modified. Rejecting changes." >&2
    echo "fix-applied=false" >> "$GITHUB_OUTPUT"
    echo "validation-passed=false" >> "$GITHUB_OUTPUT"
    return 1
  fi

  echo "[validate-paths] All changed files within allowed paths."
  return 0
}

# ── Run checks ───────────────────────────────────────────────────────
if ! check_blocked; then
  exit 1
fi

if ! check_allowed; then
  exit 1
fi

echo "[validate-paths] Safety checks passed."
echo "fix-applied=true" >> "$GITHUB_OUTPUT"
echo "validation-passed=true" >> "$GITHUB_OUTPUT"
exit 0
