#!/bin/bash
# install.sh — one-time installer for Speech2Write.
#
# Installs the app to /Applications, clears Gatekeeper quarantine, and pre-installs
# the Parakeet TDT v2 speech model so no first-run download is needed.
#
# Usage (assets in the same directory as this script):
#   ./install.sh
# Or let it fetch the latest release with the GitHub CLI (gh auth for github.com):
#   ./install.sh --fetch

set -euo pipefail

REPO="ChipmunkRPA/speech2write"
GHE_HOST="github.com"
APP_NAME="Speech2Write"
LEGACY_APP_NAME="Platypus Flow"
EXPECTED_BUNDLE_ID="com.raysang.platypusflow"
EXPECTED_TEAM_ID="49BUJ27R67"
MODEL_DIR="${HOME}/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2-coreml"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_TMP="$(mktemp -d)"
INSTALLED_APP="/Applications/${APP_NAME}.app"
LEGACY_INSTALLED_APP="/Applications/${LEGACY_APP_NAME}.app"
BACKUP_APP="/Applications/.${APP_NAME}.install-backup.$$"
BACKUP_SOURCE=""
INSTALL_COMPLETE=0

cleanup() {
  local status=$?
  trap - EXIT
  rm -rf "${INSTALL_TMP}"

  if [[ "${INSTALL_COMPLETE}" == "1" ]]; then
    rm -rf "${BACKUP_APP}"
  elif [[ -d "${BACKUP_APP}" && -n "${BACKUP_SOURCE}" ]]; then
    rm -rf "${INSTALLED_APP}"
    mv "${BACKUP_APP}" "${BACKUP_SOURCE}"
    echo "==> Installation failed; restored the previous app"
  fi

  exit "${status}"
}
trap cleanup EXIT

find_asset() { # pattern
  find "${HERE}" -maxdepth 1 -name "$1" | sort | tail -1
}

if [[ "${1:-}" == "--fetch" ]]; then
  if ! command -v gh >/dev/null; then
    echo "gh CLI not found. Download the release assets from https://${GHE_HOST}/${REPO}/releases manually," >&2
    echo "put them next to this script, and re-run without --fetch." >&2
    exit 1
  fi
  echo "==> Downloading latest release assets from ${GHE_HOST}/${REPO}"
  GH_HOST="${GHE_HOST}" gh release download --repo "${REPO}" --pattern 'Speech2Write-*' --dir "${HERE}" --clobber
  GH_HOST="${GHE_HOST}" gh release download --repo "${REPO}" --pattern 'SHA256SUMS' --dir "${HERE}" --clobber || true
fi

APP_ZIP="$(find_asset 'Speech2Write-[0-9]*.zip')"
MODEL_TAR="$(find_asset 'Speech2Write-model-parakeet-v2*.tar.gz')"

if [[ -z "${APP_ZIP}" ]]; then
  echo "App zip (Speech2Write-<version>.zip) not found next to this script." >&2
  echo "Download it from https://${GHE_HOST}/${REPO}/releases (or run with --fetch)." >&2
  exit 1
fi

# Integrity: verify SHA-256 of each asset against the release's SHA256SUMS
# before anything is installed. Set SPEECH2WRITE_SKIP_VERIFY=1 to bypass (not
# recommended; only for pre-1.2.0 releases that shipped no checksum file).
verify_asset() { # path
  local f="$1" name expected actual
  name="$(basename "$f")"
  expected="$(grep -E "  ${name}\$" "${HERE}/SHA256SUMS" | awk '{print $1}' | head -1)"
  if [[ -z "${expected}" ]]; then
    echo "ERROR: ${name} is not listed in SHA256SUMS — refusing to install." >&2
    exit 1
  fi
  actual="$(shasum -a 256 "$f" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: checksum mismatch for ${name}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    echo "The download may be corrupted or tampered with. Not installing." >&2
    exit 1
  fi
  echo "==> Verified ${name} (sha256 ok)"
}

if [[ "${SPEECH2WRITE_SKIP_VERIFY:-0}" != "1" ]]; then
  if [[ ! -f "${HERE}/SHA256SUMS" ]]; then
    echo "ERROR: SHA256SUMS not found next to this script." >&2
    echo "Download it from the same release page, or set SPEECH2WRITE_SKIP_VERIFY=1 (not recommended)." >&2
    exit 1
  fi
  verify_asset "${APP_ZIP}"
  [[ -n "${MODEL_TAR}" ]] && verify_asset "${MODEL_TAR}"
fi

echo "==> Validating signed app bundle"
ditto -x -k "${APP_ZIP}" "${INSTALL_TMP}"
CANDIDATE_APP="${INSTALL_TMP}/${APP_NAME}.app"
if [[ ! -d "${CANDIDATE_APP}" ]]; then
  echo "ERROR: ${APP_NAME}.app is missing from ${APP_ZIP}" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "${CANDIDATE_APP}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${CANDIDATE_APP}/Contents/Info.plist")"
TEAM_ID="$(codesign -dvv "${CANDIDATE_APP}" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
if [[ "${BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
  echo "ERROR: unexpected bundle identifier ${BUNDLE_ID}" >&2
  exit 1
fi
if [[ "${TEAM_ID}" != "${EXPECTED_TEAM_ID}" ]]; then
  echo "ERROR: app was not signed by expected team ${EXPECTED_TEAM_ID}" >&2
  exit 1
fi

echo "==> Closing ${APP_NAME} before update"
osascript -e "tell application id \"${EXPECTED_BUNDLE_ID}\" to quit" 2>/dev/null || true
for _ in {1..50}; do
  if ! pgrep -x "${APP_NAME}" >/dev/null && ! pgrep -x "${LEGACY_APP_NAME}" >/dev/null; then
    break
  fi
  sleep 0.1
done
if pgrep -x "${APP_NAME}" >/dev/null || pgrep -x "${LEGACY_APP_NAME}" >/dev/null; then
  echo "ERROR: the app is still running. Quit it and retry the installer." >&2
  exit 1
fi

echo "==> Installing verified ${APP_NAME}.app to /Applications"
rm -rf "${BACKUP_APP}"
if [[ -d "${INSTALLED_APP}" ]]; then
  BACKUP_SOURCE="${INSTALLED_APP}"
  mv "${INSTALLED_APP}" "${BACKUP_APP}"
elif [[ -d "${LEGACY_INSTALLED_APP}" ]]; then
  BACKUP_SOURCE="${LEGACY_INSTALLED_APP}"
  mv "${LEGACY_INSTALLED_APP}" "${BACKUP_APP}"
fi
ditto "${CANDIDATE_APP}" "${INSTALLED_APP}"
xattr -dr com.apple.quarantine "${INSTALLED_APP}" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "${INSTALLED_APP}"
INSTALL_COMPLETE=1
rm -rf "${BACKUP_APP}"
if [[ "${LEGACY_INSTALLED_APP}" != "${INSTALLED_APP}" && -d "${LEGACY_INSTALLED_APP}" ]]; then
  rm -rf "${LEGACY_INSTALLED_APP}"
fi

if [[ -n "${MODEL_TAR}" ]]; then
  if [[ -d "${MODEL_DIR}" && -f "${MODEL_DIR}/parakeet_vocab.json" ]]; then
    echo "==> Speech model already installed (${MODEL_DIR}) — skipping"
  else
    echo "==> Installing Parakeet TDT v2 speech model (one-time, no in-app download needed)"
    mkdir -p "$(dirname "${MODEL_DIR}")"
    tar -xzf "${MODEL_TAR}" -C "$(dirname "${MODEL_DIR}")"
  fi
elif [[ -d "${MODEL_DIR}" && -f "${MODEL_DIR}/parakeet_vocab.json" ]]; then
  echo "==> Existing Parakeet TDT v2 speech model retained (${MODEL_DIR})"
else
  echo "NOTE: model archive not found next to this script — the app will offer to download"
  echo "the speech model (~443 MB from huggingface.co) on first use instead."
fi

echo "==> Launching"
open "/Applications/${APP_NAME}.app"

cat <<'EONOTE'

Done. First-run checklist:
  1. Grant Microphone access when prompted.
  2. Grant Accessibility access (System Settings > Privacy & Security > Accessibility)
     so the app can type your dictation into other apps.
  3. Press your configured dictation shortcut (shown in Settings > Global Hotkey) and talk.
EONOTE
