# DriveTime — Build & Test Verification

This file records the concrete CI evidence for the delivered source tree. It
does not claim physical-device, live-AMap, or live-Siri verification.

## Validated commit

- Commit: `c186ac7` (Chinese localization of the app and Siri App Shortcut metadata)
- Product version: `0.2.0` (build `1`)
- Date: 2026-11-21 (Asia/Shanghai)

## GitHub Actions runs

| Check | Run | Result |
|---|---|---|
| iOS Device Build | https://github.com/zhw000/DriveTime/actions/runs/44895248612 | **success** |
| iOS Simulator Tests | https://github.com/zhw000/DriveTime/actions/runs/44895248663 | **success** |
| Release Unsigned IPA | see the v0.2.0 GitHub Release | **success** |

Environment reported by the workflow and xcresult:

- macOS 26 (runner label `macos-26`, xcresult reports macOS 26.7.2)
- Xcode 26.6
- iPhone 17 Pro simulator, iOS 26.5 (arm64)
- XcodeGen 2.48.0

## Test results

Unit tests:

- **63 passed**
- **0 failed**
- **1 skipped**
- The skipped test is `AppleMapLiveIntegrationTests.testAppleMapKitLiveDrivingRoute`.
  It attempted a real `MKDirections` request from the Simulator and received
  `serverUnavailable`, so it was explicitly skipped rather than faked. This means
  live Apple MapKit routing has **not** been demonstrated by CI or on a physical
  device.
- Unit coverage includes formatting, ETA/time-zone/DST, AMap v5 JSON parsing,
  TMCs and geometry validation, history persistence, cancellation, fallback,
  coordinate conversion, route planning, map viewport fitting, and the headless
  Siri query service (success, missing place, same place, search failure,
  missing AMap configuration, strategy fallback, provider fallback, and errors).

UI tests:

- **4 passed**
- **0 failed**
- Screenshots are exported as GitHub Actions artifacts and included in
  `Docs/Screenshots/` for the final UI.
- The Settings test checks the Siri/Shortcuts explanation section.
- Route-result screenshots use DEBUG-only demo data clearly labelled `演示数据`.
  They verify layout and interactions, not a live route.

## Siri / App Intents evidence

- The app target contains `DriveTimeRouteIntent`, `DriveTimeAppShortcuts`, and
  `SiriRouteQueryService`.
- The build log shows `appintentsmetadataprocessor` writing `Metadata.appintents`
  into the device `.app`.
- The generated NLU metadata is trained for **zh-Hans**, not the old `en` locale:
  `Training '用 ${+applicationName} 查询驾车时间|让 ...' for zh-Hans`.
- The app's `Info.plist` reports `CFBundleDevelopmentRegion = zh-Hans` and
  `CFBundleLocalizations = [zh-Hans]`.
- Phrases: “用 DriveTime 查询驾车时间”, “让 DriveTime 计算车程”,
  “问 DriveTime 这段路要开多久”. Siri prompts for origin and destination.
- This proves compilation, metadata extraction, and Chinese phrase training.
  It does **not** prove that a physical iPhone's Siri recognizes the phrase,
  performs the parameter prompts, or speaks the result.

## Unsigned iPhoneOS IPA

Produced by the v0.2.0 device-build run:

- File: `DriveTime-unsigned.ipa`
- Bundle ID: `com.example.drivetime`
- Version: `0.2.0` (build `1`)
- Minimum iOS: `17.0`
- SHA-256: `b47740c312ae56e0b2fccf9f6739098e2f06b9c7d0f42f17b3a37478a5a0104a`
- Size: `1,268,601` bytes
- Device `.app` size: `5.8 MB`

The package script verified:

- the product is `CFBundleSupportedPlatforms = [iPhoneOS]`
- `DTPlatformName = iphoneos`
- Mach-O is arm64 and built for `platform IOS`
- IPA contains `Payload/DriveTime.app` and no `_CodeSignature`
- no embedded provisioning profile

This artifact is **unsigned** and must be signed by the recipient. A GitHub
Release rebuild may produce a different hash; use the `checksums.txt` attached
to that Release as authoritative for the downloaded asset.

## Not verified

- Installation on a physical iPhone using the recipient's certificate/profile.
- Actual Siri voice activation, parameter prompting, spoken dialog, or snippet.
- Real AMap route queries with an actual AMap Web Service key and deployed proxy.
- A successful live Apple MapKit route query in CI (the single live test skipped
  with `serverUnavailable`).
- Full manual VoiceOver audit, all Dynamic Type sizes, every landscape layout,
  network transition edge cases, and long-duration stability.

These are explicitly listed in the README and in the real-device acceptance
checklist.
