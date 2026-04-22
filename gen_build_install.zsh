#!/bin/zsh
set -euo pipefail

SCHEME="LinkKeeper"
CONFIG="Release"
PROJECT="LinkKeeper.xcodeproj"

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
EOF
  exit 1
}

# --- Parse arguments ---
if [[ $# -eq 0 ]]; then
  usage
fi

case "$1" in
  --build-check*)
    # Parse configs: --build-check or --build-check=Debug,Release
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
    # --- Generate project ---
    echo "==> xcodegen generate"
    xcodegen generate

    # --- Build ---
    echo "==> Building $SCHEME ($CONFIG) ..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -configuration "$CONFIG" \
      build

    # --- Resolve app path ---
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
  -*)
    echo "Error: unknown option '$1'" >&2
    usage
    ;;
  *)
    echo "Error: unknown argument '$1'" >&2
    usage
    ;;
esac
