#!/usr/bin/env bash
set -euo pipefail

# install-kimchi.sh
# Downloads and installs a specific pinned version of the Kimchi CLI,
# verifies its checksum, and extracts it to a user-local directory.
# No sudo is required.

# ── Configuration (override via environment) ─────────────────────────
KIMCHI_VERSION="${KIMCHI_VERSION:-}"
KIMCHI_SHA256="${KIMCHI_SHA256:-}"
KIMCHI_PLATFORM="${KIMCHI_PLATFORM:-}"
KIMCHI_INSTALL_DIR="${KIMCHI_INSTALL_DIR:-${HOME}/.local/bin}"
KIMCHI_DOWNLOAD_BASE="${KIMCHI_DOWNLOAD_BASE:-https://get.kimchi.dev/releases}"

# ── Pre-flight checks ────────────────────────────────────────────────

if [[ -z "${KIMCHI_VERSION}" ]]; then
  echo "[install-kimchi] ERROR: KIMCHI_VERSION is not set."
  echo "[install-kimchi] You must specify a pinned version (e.g., v1.2.3)."
  echo "[install-kimchi] Using 'latest' is intentionally disallowed for supply-chain safety."
  exit 1
fi

# Auto-detect platform if not provided.
if [[ -z "${KIMCHI_PLATFORM}" ]]; then
  case "$(uname -sm)" in
    "Linux x86_64") KIMCHI_PLATFORM="linux-amd64" ;;
    "Linux aarch64") KIMCHI_PLATFORM="linux-arm64" ;;
    "Darwin x86_64") KIMCHI_PLATFORM="darwin-amd64" ;;
    "Darwin arm64")  KIMCHI_PLATFORM="darwin-arm64" ;;
    *)
      echo "[install-kimchi] ERROR: Unsupported platform: $(uname -sm)"
      exit 1
      ;;
  esac
  echo "[install-kimchi] Auto-detected platform: ${KIMCHI_PLATFORM}"
fi

TARBALL_NAME="kimchi-${KIMCHI_PLATFORM}.tar.gz"
DOWNLOAD_URL="${KIMCHI_DOWNLOAD_BASE}/${KIMCHI_VERSION}/${TARBALL_NAME}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# ── Download ─────────────────────────────────────────────────────────

echo "[install-kimchi] Downloading Kimchi ${KIMCHI_VERSION} for ${KIMCHI_PLATFORM}..."
echo "[install-kimchi] URL: ${DOWNLOAD_URL}"

curl -fsSL --retry 3 --retry-delay 2 \
  "${DOWNLOAD_URL}" \
  -o "${TMP_DIR}/${TARBALL_NAME}"

# ── Checksum verification ────────────────────────────────────────────

if [[ -n "${KIMCHI_SHA256}" ]]; then
  echo "[install-kimchi] Verifying SHA-256 checksum..."
  echo "${KIMCHI_SHA256}  ${TMP_DIR}/${TARBALL_NAME}" > "${TMP_DIR}/checksum.txt"
  if ! sha256sum -c "${TMP_DIR}/checksum.txt" >/dev/null 2>&1; then
    echo "[install-kimchi] ERROR: SHA-256 checksum verification failed!" >&2
    echo "[install-kimchi] Expected: ${KIMCHI_SHA256}" >&2
    echo "[install-kimchi] Actual:   $(sha256sum "${TMP_DIR}/${TARBALL_NAME}" | awk '{print $1}')" >&2
    exit 1
  fi
  echo "[install-kimchi] Checksum verified."
else
  echo "[install-kimchi] WARNING: No KIMCHI_SHA256 provided. Skipping checksum verification."
  echo "[install-kimchi] For supply-chain safety, always provide a SHA-256 hash when pinning a version."
fi

# ── Extract ──────────────────────────────────────────────────────────

echo "[install-kimchi] Extracting to ${KIMCHI_INSTALL_DIR}..."
mkdir -p "${KIMCHI_INSTALL_DIR}"
tar -xzf "${TMP_DIR}/${TARBALL_NAME}" -C "${KIMCHI_INSTALL_DIR}"

# Ensure the directory is on PATH for the current process.
if ! command -v kimchi &>/dev/null; then
  export PATH="${KIMCHI_INSTALL_DIR}:${PATH}"
fi

# ── Verify installation ──────────────────────────────────────────────

if command -v kimchi &>/dev/null; then
  KIMCHI_INSTALLED_VERSION="$(kimchi --version 2>/dev/null || echo "unknown")"
  echo "[install-kimchi] Kimchi installed successfully."
  echo "[install-kimchi] Version: ${KIMCHI_INSTALLED_VERSION}"
  echo "[install-kimchi] Location: ${KIMCHI_INSTALL_DIR}/kimchi"
else
  echo "[install-kimchi] ERROR: kimchi binary not found after extraction." >&2
  echo "[install-kimchi] Expected it in: ${KIMCHI_INSTALL_DIR}" >&2
  exit 1
fi

exit 0
