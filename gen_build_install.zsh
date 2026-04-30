#!/bin/zsh
set -euo pipefail

SCHEME="LinkKeeper"
CONFIG="Release"
PROJECT="LinkKeeper.xcodeproj"
NOTARY_PROFILE="${LINKKEEPER_NOTARY_PROFILE:-linkkeeper-notary}"
RELEASE_DIR="release"

usage() {
  cat <<'EOF'
Usage:
  ./gen_build_install.zsh --mac                 Build & install to /Applications
  ./gen_build_install.zsh --build-check[=configs]
                                                Build-only check (no install)
                                                configs: comma-separated Debug,Release (default: Release)
                                                Examples:
                                                  --build-check            Release only
                                                  --build-check=Debug      Debug only
                                                  --build-check=Debug,Release  both
  ./gen_build_install.zsh --release [version]   Build, sign (Developer ID), notarize, staple, zip
                                                Output: release/LinkKeeper-<version>.zip
                                                version: optional, defaults to MARKETING_VERSION

Environment:
  LINKKEEPER_NOTARY_PROFILE  notarytool keychain profile name (default: linkkeeper-notary)
                             Setup: xcrun notarytool store-credentials "linkkeeper-notary" \
                                      --apple-id <email> --team-id PNKEK75AK4 --password <app-pw>
EOF
  exit 1
}

# --- Parse arguments ---
if [[ $# -eq 0 ]]; then
  usage
fi

case "$1" in
  --build-check*)
    BC_ARG="${1#--build-check}"
    BC_ARG="${BC_ARG#=}"
    if [[ -z "$BC_ARG" ]]; then
      BC_CONFIGS=("Release")
    else
      BC_CONFIGS=("${(@s/,/)BC_ARG}")
    fi

    echo "==> xcodegen generate"
    xcodegen generate

    BC_FAILED=0
    for BC_CFG in "${BC_CONFIGS[@]}"; do
      echo "==> Build check: $SCHEME ($BC_CFG) ..."
      set +e
      xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$BC_CFG" \
        build
      BC_RC=$?
      set -e
      if [[ $BC_RC -eq 0 ]]; then
        echo "==> $BC_CFG: BUILD SUCCEEDED"
      else
        echo "==> $BC_CFG: BUILD FAILED" >&2
        BC_FAILED=1
      fi
    done

    if [[ $BC_FAILED -ne 0 ]]; then
      echo "==> Build check FAILED" >&2
      exit 1
    fi
    echo "==> All build checks passed!"
    exit 0
    ;;

  --mac|-m)
    echo "==> xcodegen generate"
    xcodegen generate

    echo "==> Building $SCHEME ($CONFIG) ..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      build

    APP_PATH="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -showBuildSettings 2>/dev/null \
      | grep -m1 ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/$SCHEME.app"

    echo "==> Installing $APP_PATH to /Applications ..."
    rm -rf "/Applications/$SCHEME.app"
    ditto "$APP_PATH" "/Applications/$SCHEME.app"

    echo "==> Done!"
    exit 0
    ;;

  --release)
    # Optional version argument
    VERSION="${2:-}"

    echo "==> xcodegen generate"
    xcodegen generate

    # Resolve version from project if not specified
    if [[ -z "$VERSION" ]]; then
      VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
        | grep -m1 ' MARKETING_VERSION' | awk '{print $3}')"
    fi
    echo "==> Release version: $VERSION"

    echo "==> Building $SCHEME ($CONFIG) with Developer ID signing ..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      CODE_SIGN_IDENTITY="Developer ID Application" \
      CODE_SIGN_STYLE=Manual \
      OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
      build

    APP_PATH="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      -showBuildSettings 2>/dev/null \
      | grep -m1 ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/$SCHEME.app"

    echo "==> Verifying signature ..."
    codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E '(Authority|TeamIdentifier|Identifier)' || true
    codesign --verify --strict --verbose=2 "$APP_PATH"

    # Prepare release dir
    mkdir -p "$RELEASE_DIR"
    NOTARIZE_ZIP="$RELEASE_DIR/$SCHEME-notarize-tmp.zip"
    FINAL_ZIP="$RELEASE_DIR/$SCHEME-$VERSION.zip"

    echo "==> Zipping for notarization ..."
    rm -f "$NOTARIZE_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

    echo "==> Submitting to Apple notary service (profile: $NOTARY_PROFILE) ..."
    SUBMIT_LOG="$RELEASE_DIR/notarize-submit.log"
    set +e
    xcrun notarytool submit "$NOTARIZE_ZIP" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait 2>&1 | tee "$SUBMIT_LOG"
    NOTARY_RC=$?
    set -e

    SUBMISSION_ID="$(grep -m1 -E '^[[:space:]]+id:' "$SUBMIT_LOG" | awk '{print $2}')"
    STATUS="$(grep -m1 -E '^[[:space:]]+status:' "$SUBMIT_LOG" | awk '{print $2}')"

    if [[ "$STATUS" != "Accepted" ]]; then
      echo "==> Notarization failed (status: $STATUS). Fetching log ..." >&2
      if [[ -n "$SUBMISSION_ID" ]]; then
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2
      fi
      exit 1
    fi

    echo "==> Stapling notary ticket to .app ..."
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"

    echo "==> Creating final release zip ..."
    rm -f "$FINAL_ZIP" "$NOTARIZE_ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

    echo ""
    echo "==> Release ready: $FINAL_ZIP"
    echo "    Upload to GitHub: gh release create v$VERSION $FINAL_ZIP --title 'v$VERSION' --notes '...'"
    exit 0
    ;;

  -*)
    echo "Error: unknown option '$1'" >&2
    usage
    ;;
  *)
    echo "Error: unknown argument '$1'" >&2
    usage
    ;;
esac
