#!/usr/bin/env bash
#
# Verify the structure of an unsigned iPhoneOS IPA produced by DriveTime CI.
#
# Usage: scripts/verify-ipa.sh path/to/DriveTime-unsigned.ipa
#
set -euo pipefail

IPA_PATH="${1:?usage: verify-ipa.sh <ipa>}"
[[ -f "$IPA_PATH" ]] || { echo "error: IPA not found: $IPA_PATH" >&2; exit 1; }

unzip -tqq "$IPA_PATH" >/dev/null
LISTING="$(unzip -Z1 "$IPA_PATH")"
APP_PREFIX="$(printf '%s\n' "$LISTING" | grep -m1 '^Payload/[^/]*\.app/Info\.plist$' | sed 's#/Info.plist$##' || true)"
[[ -n "$APP_PREFIX" ]] || { echo "error: IPA has no Payload/<App>.app/Info.plist" >&2; exit 1; }
[[ "$(printf '%s\n' "$LISTING" | grep -c '^Payload/[^/]*\.app/')" -gt 0 ]] || { echo "error: empty Payload app" >&2; exit 1; }
printf '%s\n' "$LISTING" | grep -q "^${APP_PREFIX}/_CodeSignature/" && {
  echo "error: IPA contains an embedded code signature; refusing to call it unsigned" >&2
  exit 1
} || true
printf '%s\n' "$LISTING" | grep -q "^${APP_PREFIX}/embedded.mobileprovision$" && {
  echo "error: IPA contains an embedded provisioning profile" >&2
  exit 1
} || true

TMP="$(mktemp -d "${TMPDIR:-/tmp}/drivetime-verify.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
unzip -qq "$IPA_PATH" -d "$TMP"
APP="$TMP/$APP_PREFIX"
[[ -d "$APP" ]] || { echo "error: extracted app missing" >&2; exit 1; }

PLATFORM="$(plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$APP/Info.plist" 2>/dev/null || true)"
[[ "$PLATFORM" == "iPhoneOS" ]] || { echo "error: app is not iPhoneOS ($PLATFORM)" >&2; exit 1; }
DT_PLATFORM="$(plutil -extract DTPlatformName raw -o - "$APP/Info.plist" 2>/dev/null || true)"
[[ "$DT_PLATFORM" == "iphoneos" ]] || { echo "error: DTPlatformName is $DT_PLATFORM" >&2; exit 1; }
EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP/Info.plist")"
[[ -f "$APP/$EXECUTABLE" ]] || { echo "error: executable missing" >&2; exit 1; }
BUILD_PLATFORM="$(vtool -show-build "$APP/$EXECUTABLE" 2>/dev/null | tr -d ' ' | grep -m1 '^platform:' || true)"
[[ "$BUILD_PLATFORM" == "platform:IOS" ]] || { echo "error: Mach-O platform is $BUILD_PLATFORM" >&2; exit 1; }
ARCHS="$(lipo -archs "$APP/$EXECUTABLE")"
[[ "$ARCHS" == *arm64* ]] || { echo "error: missing arm64 slice ($ARCHS)" >&2; exit 1; }

printf 'IPA structure valid: %s\n  %s\n  platform=%s minOS=%s archs=%s\n' \
  "$IPA_PATH" "$APP_PREFIX" "$PLATFORM" \
  "$(plutil -extract MinimumOSVersion raw -o - "$APP/Info.plist")" "$ARCHS"
