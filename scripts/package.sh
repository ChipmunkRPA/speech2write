#!/bin/bash
# package.sh — build and bundle "Speech2Write.app" with SwiftPM only (no Xcode required).
#
# Produces:
#   dist/Speech2Write.app
#   dist/Speech2Write-<version>.zip
#
# Requirements: macOS 15+ (Apple Silicon), Xcode Command Line Tools (swift, iconutil,
# codesign, ditto, plutil). actool is NOT required — the asset catalog is not compiled;
# named images are bundled as loose PNGs (NSImage falls back to bundle image files).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Speech2Write"
DIST="${REPO_DIR}/dist"
APP="${DIST}/${APP_NAME}.app"
BUILD_BIN="${REPO_DIR}/.build/release/FluidVoice"
ASSETS="${REPO_DIR}/Sources/Fluid/Assets.xcassets"

echo "==> Building (swift build -c release)"
cd "${REPO_DIR}"
swift build -c release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${REPO_DIR}/Info.plist")"
echo "==> Packaging ${APP_NAME} ${VERSION}"

rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

# Binary (SwiftPM target is FluidVoice; bundle executable is the display name)
cp "${BUILD_BIN}" "${APP}/Contents/MacOS/${APP_NAME}"

# Info.plist + PkgInfo
cp "${REPO_DIR}/Info.plist" "${APP}/Contents/Info.plist"
plutil -lint "${APP}/Contents/Info.plist" >/dev/null
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# App icon: iconset from AppIcon.appiconset -> AppIcon.icns
PACKAGE_TMP="$(mktemp -d)"
trap 'rm -rf "${PACKAGE_TMP}"' EXIT
ICONSET="${PACKAGE_TMP}/AppIcon.iconset"
mkdir -p "${ICONSET}"
declare -a ICON_MAP=(
  "icon-16@1x.png:icon_16x16.png"    "icon-16@2x.png:icon_16x16@2x.png"
  "icon-32@1x.png:icon_32x32.png"    "icon-32@2x.png:icon_32x32@2x.png"
  "icon-128@1x.png:icon_128x128.png" "icon-128@2x.png:icon_128x128@2x.png"
  "icon-256@1x.png:icon_256x256.png" "icon-256@2x.png:icon_256x256@2x.png"
  "icon-512@1x.png:icon_512x512.png" "icon-512@2x.png:icon_512x512@2x.png"
)
for pair in "${ICON_MAP[@]}"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  cp "${ASSETS}/AppIcon.appiconset/${src}" "${ICONSET}/${dst}"
done
iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns"

# Named images: copy every imageset's files into Resources under the ASSET name
# (Contents.json filename -> <ImagesetName>[@2x|@3x].png), so NSImage(named:)/Image(_:)
# loose-file fallback resolves them without a compiled Assets.car.
python3 - "$ASSETS" "${APP}/Contents/Resources" <<'PYEOF'
import json, os, shutil, sys
assets, res = sys.argv[1], sys.argv[2]
for entry in sorted(os.listdir(assets)):
    if not entry.endswith(".imageset"):
        continue
    name = entry[: -len(".imageset")]
    cj = os.path.join(assets, entry, "Contents.json")
    with open(cj) as fh:
        images = json.load(fh).get("images", [])
    for img in images:
        fn = img.get("filename")
        if not fn:
            continue
        scale = img.get("scale", "1x")
        suffix = "" if scale == "1x" else f"@{scale}"
        ext = os.path.splitext(fn)[1]
        shutil.copy(os.path.join(assets, entry, fn), os.path.join(res, f"{name}{suffix}{ext}"))
        print(f"  bundled {name}{suffix}{ext}")
PYEOF

# Loose resources (sounds, default vocabulary)
cp "${REPO_DIR}"/Sources/Fluid/Resources/* "${APP}/Contents/Resources/"

# SwiftPM-generated dependency resource bundles (MediaRemoteAdapter needs its run.pl)
find "${REPO_DIR}/.build/release/" -maxdepth 1 -name "*.bundle" -exec cp -R {} "${APP}/Contents/Resources/" \;

# SwiftPM-built dynamic libraries (e.g. libMediaRemoteAdapter.dylib). The executable
# resolves them via @rpath with @executable_path in its rpath list, so they live
# next to the binary in Contents/MacOS.
find "${REPO_DIR}/.build/release/" -maxdepth 1 -name "*.dylib" -exec cp {} "${APP}/Contents/MacOS/" \;

# SwiftPM dependency resources can be read-only, and source assets may carry local
# quarantine metadata. Normalize owner permissions and remove quarantine before sealing
# the bundle so future installers can safely clear download quarantine without touching
# unrelated provenance metadata.
chmod -R u+rwX "${APP}"
xattr -dr com.apple.quarantine "${APP}" 2>/dev/null || true

# Sign with a stable Developer ID identity whenever one is available. Unlike an
# ad-hoc signature, a Developer ID signature keeps the same designated
# requirement across rebuilds, so macOS Accessibility approval remains valid
# after an app update. Set SPEECH2WRITE_SIGNING_IDENTITY to choose a specific
# identity; otherwise use the first available Developer ID Application identity.
SIGNING_IDENTITY="${SPEECH2WRITE_SIGNING_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application:/ { print $2; exit }')"
fi
if [[ -z "${SIGNING_IDENTITY}" && "${SPEECH2WRITE_ALLOW_ADHOC:-0}" == "1" ]]; then
  SIGNING_IDENTITY="-"
  echo "==> WARNING: no Developer ID identity found; using explicitly allowed ad-hoc signing"
elif [[ -z "${SIGNING_IDENTITY}" ]]; then
  echo "ERROR: no Developer ID Application identity found." >&2
  echo "Set SPEECH2WRITE_SIGNING_IDENTITY, or set SPEECH2WRITE_ALLOW_ADHOC=1 for a local-only build." >&2
  exit 1
else
  echo "==> Signing with ${SIGNING_IDENTITY}"
fi

SIGNING_ARGS=(--force --options runtime --sign "${SIGNING_IDENTITY}")
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  SIGNING_ARGS+=(--timestamp)
fi

# Sign nested code first, then seal the outer bundle. Avoid --deep while signing:
# it can hide missing or incorrectly signed nested code.
find "${APP}/Contents/MacOS" -name "*.dylib" -exec codesign "${SIGNING_ARGS[@]}" {} \;
codesign "${SIGNING_ARGS[@]}" \
  --entitlements "${REPO_DIR}/Speech2Write.entitlements" \
  "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
CS_FLAGS="$(codesign -d --verbose=2 "${APP}" 2>&1 | grep '^CodeDirectory' || true)"
case "${CS_FLAGS}" in
  *runtime*) echo "==> Hardened runtime enabled" ;;
  *) echo "ERROR: hardened runtime flag missing (${CS_FLAGS})"; exit 1 ;;
esac
if [[ "${SIGNING_IDENTITY}" != "-" ]]; then
  TEAM_ID="$(codesign -dvv "${APP}" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2; exit }')"
  if [[ -z "${TEAM_ID}" || "${TEAM_ID}" == "not set" ]]; then
    echo "ERROR: packaged app is missing a stable TeamIdentifier" >&2
    exit 1
  fi
  echo "==> Verified Developer ID team ${TEAM_ID}"
fi

# Zip for release
ZIP="${DIST}/Speech2Write-${VERSION}.zip"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

# Optionally submit the release to Apple's notary service. Store credentials once with
# `xcrun notarytool store-credentials <profile>`, then pass that profile name through
# SPEECH2WRITE_NOTARY_PROFILE. Recreate the archive after stapling so downloads include the ticket.
if [[ -n "${SPEECH2WRITE_NOTARY_PROFILE:-}" ]]; then
  echo "==> Submitting release for notarization"
  xcrun notarytool submit "${ZIP}" --keychain-profile "${SPEECH2WRITE_NOTARY_PROFILE}" --wait
  xcrun stapler staple "${APP}"
  xcrun stapler validate "${APP}"
  rm -f "${ZIP}"
  ditto -c -k --keepParent "${APP}" "${ZIP}"
  spctl --assess --type execute --verbose=2 "${APP}"
elif [[ "${SPEECH2WRITE_REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  echo "ERROR: SPEECH2WRITE_REQUIRE_NOTARIZATION=1 but SPEECH2WRITE_NOTARY_PROFILE is unset." >&2
  exit 1
else
  echo "==> WARNING: release is Developer-ID signed but not notarized"
fi

# SHA-256 checksums for release assets. install.sh verifies against this file
# before installing. Set SPEECH2WRITE_MODEL_TARBALL to include the model asset.
SUMS="${DIST}/SHA256SUMS"
(
  cd "${DIST}"
  shasum -a 256 "$(basename "${ZIP}")" > "${SUMS}"
  if [[ -n "${SPEECH2WRITE_MODEL_TARBALL:-}" && -f "${SPEECH2WRITE_MODEL_TARBALL}" ]]; then
    MODEL_DIR_PATH="$(cd "$(dirname "${SPEECH2WRITE_MODEL_TARBALL}")" && pwd)"
    (cd "${MODEL_DIR_PATH}" && shasum -a 256 "$(basename "${SPEECH2WRITE_MODEL_TARBALL}")") >> "${SUMS}"
  fi
)

echo "==> Done"
echo "    ${APP}"
echo "    ${ZIP}"
echo "    ${SUMS}"
