# CI/CD Debug Log

## Deployment issues in chronological order

| # | Issue | Approach | Result | Status |
|---|-------|----------|--------|--------|
| 1 | Dart SDK ^3.10.4 requires Flutter 3.29.2+ | Updated FLUTTER_VERSION to 3.41.9 (matches .fvmrc) | ✅ | **FIXED** |
| 2 | SSH authentication failed for certificates repo | Generated SSH key pair + deploy key on ios-certificates repo + MATCH_SSH_PRIVATE_KEY secret | ✅ | **FIXED** |
| 3 | `your-org/ios-certificates` repo not found | Updated Matchfile URL to `rizzojr01/ios-certificates` | ✅ | **FIXED** |
| 4 | No code signing identity in readonly mode | Ran `fastlane match appstore` locally to generate + push certs | ✅ | **FIXED** |
| 5 | `No Accounts` error - automatic signing needs Apple ID on CI | Set CODE_SIGN_STYLE=Manual via xcargs | ❌ | **ABANDONED** (use update_code_signing_settings instead) |
| 6 | `requires a provisioning profile` - manual signing needs specifier | Added PROVISIONING_PROFILE_SPECIFIER in xcargs | ❌ | **ABANDONED** (use update_code_signing_settings instead) |
| 7 | RunnerTests looking for iOS Development certificate | Added `update_code_signing_settings` for RunnerTests target | ❌ | **PARTIAL** (need to disable signing for RunnerTests) |
| 8 | api_key `invalid curve name` on Ruby 3.2.11/OpenSSL | Removed `app_store_connect_api_key` action, rely on env vars auto-detection | ✅ | **FIXED** |
| 9 | `update_code_signing_settings` without profile leaves Xcode clueless | Added back team_id + profile_name + targets + bundle_identifier | ✅ | **FIXED** |
| 10 | `build_app` missing export options | Added export_method + export_options.provisioningProfiles + destination | ✅ | **FIXED** |
| 11 | upload_to_testflight might need app_identifier | TBD if needed: add `app_identifier: app_identifier` back | ⏳ | **UNTESTED** (build hasn't completed yet) |
| 12 | `No signing certificate "iOS Development" found` - Xcode looks for dev cert instead of distribution | Added `code_sign_identity: "Apple Distribution"` to update_code_signing_settings | ✅ | **FIXED** (build now passes certificate check) |
| 13 | Build stuck at "Run Script" for 21+ minutes with no log output | Added diagnostics: verbose logging, clean build, system info, macos-14 runner | 🔄 | **INVESTIGATING** (likely AOT compilation hang or memory pressure) |
| 14 | `could not find included file 'Generated.xcconfig'` - Flutter build files missing after clean | Added `flutter build ios --config-only --no-codesign` before fastlane | ✅ | **FIXED** |
| 15 | `camera_avfoundation` compilation errors - plugin uses unavailable AVCaptureSession APIs | camera 0.12.0+1 still has iOS 17.5 SDK incompatibility | ❌ | **BLOCKING** (camera plugin bug, need to remove or wait for fix) |

## Current State

**What's working:**
- ✅ SSH key authentication for certificates repo
- ✅ Match downloads correct distribution certificates
- ✅ Code signing identity correctly set to "Apple Distribution"
- ✅ Provisioning profiles mapped correctly
- ✅ Build passes certificate validation (all signing issues resolved!)
- ✅ Generated.xcconfig created before Xcode build
- ✅ iOS 13.0 deployment target set
- ✅ Firebase Swift 5.0 compatibility

**Current blocker:**
- ❌ `camera_avfoundation-0.10.1` fails compilation on iOS 17.5 SDK
  - Error: `AVCaptureSession` has no member `wasInterruptedNotification`
  - This is a **camera plugin bug**, not a signing/build config issue
  - Even latest camera version (0.12.0+1) has this problem

**Options to proceed:**
1. **Remove camera package** temporarily → Build succeeds, deploy to TestFlight
2. **Wait for camera plugin fix** → Blocked indefinitely
3. **Fork and patch camera** → High effort, maintain fork

**Recommendation:** Remove camera from pubspec.yaml, deploy to TestFlight, re-add when plugin is fixed.

**Diagnostics added:**
- System info (Xcode version, Ruby, memory, disk)
- Verbose fastlane logging
- Clean build before each run
- Switched to macos-14 runner (more stable)
- Extended timeout to 60 minutes
- Artifact upload for build logs
- Flutter config-only build to generate required files

(End of file - total 50 lines)
