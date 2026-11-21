# DriveTime — Build & Test Verification

This file records the concrete CI evidence for the delivered source tree. It
does not claim physical-device or live-AMap verification.

## Validated commit

- Commit: `4760b6058b82f9d1b0e45bc733922a4e50d8256d` (`4760b60`)
- Message: `Clean result map overlay and stabilize UI test timing`
- Date: 2026-11-21 (Asia/Shanghai)

## GitHub Actions runs

| Check | Run | Result |
|---|---|---|
| iOS Device Build | https://github.com/zhw000/DriveTime/actions/runs/44882877727 | **success** |
| iOS Simulator Tests | https://github.com/zhw000/DriveTime/actions/runs/44882877674 | **success** |

Environment reported by the workflow and xcresult:

- macOS 26 (runner label `macos-26`, xcresult reports macOS 26.7.2)
- Xcode 26.6
- iPhone 17 Pro simulator, iOS 26.5 (arm64)
- XcodeGen 2.48.0

## Test results

Unit tests:

- **54 passed**
- **0 failed**
- **1 skipped**
- The skipped test is `AppleMapLiveIntegrationTests.testAppleMapKitLiveDrivingRoute`.
  It attempted a real `MKDirections` request from the Simulator and received
  `serverUnavailable`, so it was explicitly skipped rather than faked. This means
  live Apple MapKit routing has **not** been demonstrated by CI or on a physical
  device.
- Unit coverage includes formatting, ETA/time-zone/DST, AMap v5 JSON parsing,
  TMCs and geometry validation, history persistence, cancellation, fallback,
  coordinate conversion, route planning, and map viewport fitting.

UI tests:

- **4 passed**
- **0 failed**
- Screenshots are exported as GitHub Actions artifacts and included in
  `Docs/Screenshots/` for the final UI.
- Route-result screenshots use DEBUG-only demo data clearly labelled `演示数据`.
  They verify layout and interactions, not a live route.

## Unsigned iPhoneOS IPA

Produced by the device-build run:

- File: `DriveTime-unsigned.ipa`
- Bundle ID: `com.example.drivetime`
- Version: `0.1.0` (build `1`)
- Minimum iOS: `17.0`
- SHA-256: `b195718ff59464a97b11b6be4458b0e9ae81c0de0c2b5152756e24ea583cabe4`
- Size: `1,221,445` bytes
- Device `.app` size: `5.6 MB`

The package script verified:

- the product is `CFBundleSupportedPlatforms = [iPhoneOS]`
- `DTPlatformName = iphoneos`
- Mach-O is arm64 and built for `platform IOS`
- IPA contains `Payload/DriveTime.app` and no `_CodeSignature`
- no embedded provisioning profile

This artifact is **unsigned** and must be signed by the recipient. A later
GitHub Release may rebuild the IPA; use `checksums.txt` from that Release as the
authoritative hash for the downloaded file.

## Not verified

- Installation on a physical iPhone using the recipient's certificate/profile.
- Real AMap route queries with an actual AMap Web Service key and deployed proxy.
- A successful live Apple MapKit route query in CI (the single live test skipped
  with `serverUnavailable`).
- Full manual VoiceOver audit, all Dynamic Type sizes, every landscape layout,
  network transition edge cases, and long-duration stability.

These are explicitly listed in the README and in the real-device acceptance
checklist.
