#!/usr/bin/env bash
#
# Regenerate DriveTime.xcodeproj from project.yml on macOS.
# The CI workflow performs the same steps with a pinned XcodeGen version.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.48.0}"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "XcodeGen is a macOS tool and this host is not macOS." >&2
    echo "Generate the project in GitHub Actions or on a Mac." >&2
    exit 1
  fi
  echo "Installing XcodeGen ${XCODEGEN_VERSION}..."
  mkdir -p .tools
  curl --fail --silent --show-error --location \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip" \
    -o .tools/xcodegen.zip
  rm -rf .tools/xcodegen
  unzip -q .tools/xcodegen.zip -d .tools
  export PATH="$ROOT_DIR/.tools/xcodegen/bin:$PATH"
fi

xcodegen --version
xcodegen generate --spec project.yml
echo "Generated DriveTime.xcodeproj from project.yml"
