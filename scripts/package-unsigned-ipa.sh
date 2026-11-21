#!/usr/bin/env bash
#
# Package an unsigned iPhoneOS .app as a conventional Payload/ IPA.
# Intended to run on a macOS GitHub Actions runner (uses Apple's ditto,
# plutil, vtool and lipo).
#
# Usage: scripts/package-unsigned-ipa.sh [APP_PATH] [OUTPUT_DIR]
#
set -euo pipefail

APP_PATH="${1:-build/Build/Products/Release-iphoneos/DriveTime.app}"
OUTPUT_DIR="${2:-artifacts}"
IPA_NAME="${IPA_NAME:-DriveTime-unsigned.ipa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "==> $*"
}

[[ -d "$APP_PATH" ]] || fail "device build product not found: $APP_PATH"
[[ -f "$APP_PATH/Info.plist" ]] || fail "app bundle has no Info.plist: $APP_PATH"
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

PLATFORM="$(plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ "$PLATFORM" == "iPhoneOS" ]] || fail "refusing to package a non-iPhoneOS bundle (CFBundleSupportedPlatforms.0=$PLATFORM)"

DT_PLATFORM="$(plutil -extract DTPlatformName raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ "$DT_PLATFORM" == "iphoneos" ]] || fail "refusing to package a non-iphoneos bundle (DTPlatformName=$DT_PLATFORM)"

MIN_OS="$(plutil -extract MinimumOSVersion raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ -n "$MIN_OS" ]] || fail "app is missing MinimumOSVersion"

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
[[ -n "$BUNDLE_ID" && -n "$EXECUTABLE" ]] || fail "app Info.plist has no bundle identifier or executable"
[[ -f "$APP_PATH/$EXECUTABLE" ]] || fail "app executable missing: $APP_PATH/$EXECUTABLE"

note "Checking the binary is a genuine arm64 iPhoneOS executable"
file "$APP_PATH/$EXECUTABLE"
ARCHS="$(lipo -archs "$APP_PATH/$EXECUTABLE" 2>/dev/null || true)"
[[ "$ARCHS" == *arm64* ]] || fail "binary is not arm64: $ARCHS"
BUILD_INFO="$(vtool -show-build "$APP_PATH/$EXECUTABLE" 2>/dev/null || true)"
if ! printf '%s\n' "$BUILD_INFO" | grep -Eq 'platform[: ]+IOS'; then
  echo "$BUILD_INFO" >&2
  fail "binary is not an iPhoneOS Mach-O (vtool did not report platform IOS)"
fi
BUILD_PLATFORM="IOS"

printf 'Bundle:      %s\nVersion:     %s (%s)\nMinimum iOS: %s\nPlatform:    %s / %s\nArchitectures: %s\n' \
  "$BUNDLE_ID" \
  "$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Info.plist" 2>/dev/null || echo unknown)" \
  "$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Info.plist" 2>/dev/null || echo unknown)" \
  "$MIN_OS" "$PLATFORM" "$DT_PLATFORM" "$ARCHS"

note "Staging Payload"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/drivetime-ipa.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Payload"
ditto "$APP_PATH" "$STAGING/Payload/$(basename "$APP_PATH")"

# Never ship a stale signature or provisioning profile in the unsigned IPA.
if [[ -d "$STAGING/Payload/$(basename "$APP_PATH")/_CodeSignature" ]]; then
  echo "warning: removing _CodeSignature from unsigned build" >&2
  rm -rf "$STAGING/Payload/$(basename "$APP_PATH")/_CodeSignature"
fi
if [[ -f "$STAGING/Payload/$(basename "$APP_PATH")/embedded.mobileprovision" ]]; then
  echo "warning: removing embedded.mobileprovision from unsigned build" >&2
  rm -f "$STAGING/Payload/$(basename "$APP_PATH")/embedded.mobileprovision"
fi

IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
rm -f "$IPA_PATH"
note "Creating $IPA_PATH"
(
  cd "$STAGING"
  ditto -c -k --sequesterRsrc --keepParent Payload "$IPA_PATH"
)

note "Verifying IPA structure"
"$SCRIPT_DIR/verify-ipa.sh" "$IPA_PATH"

IPA_BYTES="$(stat -f%z "$IPA_PATH")"
SHA256="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
IPHONEOS_APP_SIZE="$(du -sh "$APP_PATH" | awk '{print $1}')"
CHECKSUMS="$OUTPUT_DIR/checksums.txt"
{
  echo "# DriveTime unsigned IPA checksums"
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ipa_sha256=$SHA256"
  echo "ipa_bytes=$IPA_BYTES"
  echo "ipa=$(basename "$IPA_PATH")"
  echo "bundle_id=$BUNDLE_ID"
  echo "version=$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Info.plist")"
  echo "build=$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Info.plist")"
  echo "minimum_ios=$MIN_OS"
  echo "device_app_size=$IPHONEOS_APP_SIZE"
} > "$CHECKSUMS"

note "IPA created successfully"
printf 'Path:    %s\nSize:    %s bytes\nSHA-256: %s\n' "$IPA_PATH" "$IPA_BYTES" "$SHA256"
echo "This is an UNSIGNED device IPA. The user must sign it with a valid certificate, provisioning profile and matching bundle identifier."
