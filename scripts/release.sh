#!/bin/bash
# Mosaic release pipeline.
#
# Default (no flags): build Release, ditto-zip, print SHA256 + next steps.
# --publish: also create the GitHub release + update the homebrew-mosaic
#            cask (sibling dir) + push the tap.
#
# Reads the version from project.yml's MARKETING_VERSION.
# Requires: xcodegen, xcodebuild. --publish additionally needs gh CLI and
# the homebrew-mosaic repo cloned next to this one.

set -euo pipefail

PUBLISH=false
if [[ "${1:-}" == "--publish" ]]; then
    PUBLISH=true
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(grep -E '^[[:space:]]+MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
if [[ -z "$VERSION" ]]; then
    echo "error: couldn't read MARKETING_VERSION from project.yml" >&2
    exit 1
fi

ZIP_NAME="Mosaic-${VERSION}.zip"
ZIP_PATH="${REPO_ROOT}/${ZIP_NAME}"
APP_PATH="build/Build/Products/Release/Mosaic.app"
TAP_DIR="$(cd "${REPO_ROOT}/.." && pwd)/homebrew-mosaic"

echo "==> Mosaic v${VERSION}"

# --- Build ---
echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Building Release configuration (this can take a minute)"
rm -rf build
if ! xcodebuild -project Mosaic.xcodeproj -scheme Mosaic \
                -configuration Release \
                -derivedDataPath build \
                build > /tmp/mosaic-release-build.log 2>&1; then
    echo "error: build failed. Last 30 lines:" >&2
    tail -30 /tmp/mosaic-release-build.log >&2
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build succeeded but $APP_PATH not found" >&2
    exit 1
fi

# --- Zip ---
echo "==> Zipping → ${ZIP_NAME}"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# --- SHA ---
SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

echo ""
echo "============================================================"
echo "  Artifact: $ZIP_PATH"
echo "  Size:     $(du -h "$ZIP_PATH" | awk '{print $1}')"
echo "  SHA256:   $SHA"
echo "============================================================"
echo ""

if [[ "$PUBLISH" != "true" ]]; then
    cat <<EOF
Dry run done. To publish:

  scripts/release.sh --publish

Or manually:
  1. Create release on GitHub:
       gh release create v${VERSION} ${ZIP_NAME} --title "v${VERSION}" --notes "Mosaic v${VERSION}"
  2. Update Casks/mosaic.rb in homebrew-mosaic:
       version "${VERSION}"
       sha256  "${SHA}"
  3. Commit + push the tap.
EOF
    exit 0
fi

# --- Publish: GitHub release ---
if ! command -v gh >/dev/null 2>&1; then
    echo "error: --publish requires the gh CLI" >&2
    exit 1
fi

echo "==> Creating GitHub release v${VERSION}"
if gh release view "v${VERSION}" >/dev/null 2>&1; then
    echo "    v${VERSION} already exists — uploading asset to it"
    gh release upload "v${VERSION}" "$ZIP_PATH" --clobber
else
    gh release create "v${VERSION}" "$ZIP_PATH" \
        --title "v${VERSION}" \
        --notes "Mosaic v${VERSION}"
fi

# --- Publish: update the tap ---
if [[ ! -d "${TAP_DIR}/.git" ]]; then
    echo ""
    echo "warning: homebrew-mosaic not found at ${TAP_DIR}"
    echo "         Update the cask manually:"
    echo "           version \"${VERSION}\""
    echo "           sha256  \"${SHA}\""
    exit 0
fi

CASK="${TAP_DIR}/Casks/mosaic.rb"
if [[ ! -f "$CASK" ]]; then
    echo "warning: $CASK not found — skipping tap update" >&2
    exit 0
fi

echo "==> Updating ${CASK}"
# Bump version and replace sha256 line (handles both :no_check and real hashes).
sed -i '' -E "s|^([[:space:]]*)version \".*\"|\\1version \"${VERSION}\"|" "$CASK"
sed -i '' -E "s|^([[:space:]]*)sha256.*|\\1sha256 \"${SHA}\"|" "$CASK"

cd "$TAP_DIR"
if git diff --quiet Casks/mosaic.rb; then
    echo "    cask already at v${VERSION} / ${SHA:0:12}… — nothing to commit"
else
    git add Casks/mosaic.rb
    git commit -m "mosaic ${VERSION}" >/dev/null
    git push >/dev/null
    echo "==> Tap pushed"
fi

echo ""
echo "Done. Anyone can now install with:"
echo "  brew install --cask erwinzhang7/mosaic/mosaic"
