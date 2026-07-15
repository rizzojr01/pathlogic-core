# iOS Account Migration: Personal → TaggedWeb Inc. Org

## Goal
Migrate the PathLogic app (`com.pathlogic.core`) from Surendhar's personal Apple Developer account to the TaggedWeb Inc. organization account, make automatic signing work for local development, and deploy the first build to TestFlight.

---

## Current Status

| Step | Status |
|------|--------|
| Archive with manual signing | ✅ Done |
| Automatic signing for local dev | ❌ Not working — needs registered devices |
| Upload to TestFlight | ❌ Blocked — need to export IPA first |

---

## Why Automatic Signing Is Failing

### Root Cause: No Registered Devices Under the Org Account

Automatic signing requires **at least one registered device** (iPhone/Mac UDID) under the organization's Apple Developer account. When Xcode tries to auto-sign, it:

1. Contacts Apple's servers to generate a provisioning profile
2. Apple's servers check for registered devices under team `3AKM83DNCV`
3. **No devices exist** → fails with: *"Your team has no devices from which to generate a provisioning profile"*

### Two Separate Signing Scenarios

| Scenario | Signing Type | What It Does | Needs Devices? | Used For |
|----------|-------------|--------------|----------------|----------|
| **Local development** | Automatic (Apple Development) | Generates development profiles per-device | Yes — at least one device UDID | Running app on physical device from Xcode |
| **TestFlight/App Store** | Manual (Apple Distribution) | Uses a pre-created distribution profile | No | Building archive for Transporter/upload |

**Automatic signing CAN work** for local development once devices are registered. It will generate **Apple Development** provisioning profiles automatically. You still need **manual signing** for the actual TestFlight archive — this is an Apple requirement, not a limitation.

### Summary

| Issue | Why It Fails | Fix |
|-------|-------------|-----|
| No registered devices | Xcode can't generate any provisioning profile | Register Mac + test device UDIDs |
| Keychain trust | Imported certs need proper trust settings for `codesign` | Set trust to "Use System Defaults" |
| Keychain ACL | `codesign` blocked from accessing private key | Run `security set-key-partition-list` or allow in Keychain Access |

---

## User Stories

### US-01: Register Devices for Automatic Signing (Local Dev)
**As a** developer,
**I want** to register my Mac and test devices under the TaggedWeb Inc. org,
**So that** automatic signing can generate development provisioning profiles for local testing.

**Acceptance Criteria:**
- [ ] Register Mac's UDID at developer.apple.com/account/resources/devices
- [ ] Register test iPhone/iPad UDIDs
- [ ] Xcode shows TaggedWeb Inc. as a valid team with automatic signing
- [ ] Debug config uses `CODE_SIGN_STYLE = Automatic`

**Why needed:** Without registered devices, Xcode automatic signing cannot generate any provisioning profiles at all. This is the single blocker for automatic signing.

**How to get Mac UDID:**
- Apple menu → About This Mac → System Report → Hardware → look for "Hardware UUID"
- Or: `system_profiler SPHardwareDataType | grep "Hardware UUID"`

**Status:** ❌ Not started

---

### US-02: Create Distribution Certificate
**As a** developer,
**I want** an Apple Distribution certificate under the TaggedWeb Inc. org (team `3AKM83DNCV`),
**So that** I can sign production builds for TestFlight and App Store.

**Acceptance Criteria:**
- [ ] Certificate created at developer.apple.com/account/resources/certificates
- [ ] Type: **Apple Distribution** (not Development)
- [ ] Certificate installed in Keychain Access with private key
- [ ] Trust settings set to **"Use System Defaults"** (not "Always Trust")
- [ ] `security find-identity -v -p codesigning` shows the distribution identity

**Status:** ✅ Done — `iPhone Distribution: TaggedWeb Inc. (3AKM83DNCV)` installed

---

### US-03: Create App Store Provisioning Profile
**As a** developer,
**I want** an App Store Connect provisioning profile for `com.pathlogic.core` under the TaggedWeb Inc. org,
**So that** the build can be signed for TestFlight/App Store distribution.

**Acceptance Criteria:**
- [ ] Profile type: **App Store Connect** (not Ad Hoc)
- [ ] App ID: `com.pathlogic.core`
- [ ] Certificate: Apple Distribution (from US-02)
- [ ] Capabilities: **Push Notifications** enabled
- [ ] Profile downloaded and installed in `~/Library/MobileDevice/Provisioning Profiles/`
- [ ] Profile UUID: `88f81042-4655-4c63-a9ad-33f0fe6dc0ff`
- [ ] Profile name: `tweb-pathlogic`

**Status:** ✅ Done

---

### US-04: Configure Xcode Project for Org Account
**As a** developer,
**I want** the Xcode project updated with the new org team ID, bundle ID, and signing settings,
**So that** builds use the TaggedWeb Inc. credentials instead of the personal account.

**Acceptance Criteria:**
- [ ] `DEVELOPMENT_TEAM` = `3AKM83DNCV` (all configs: Debug, Release, Profile)
- [ ] `PRODUCT_BUNDLE_IDENTIFIER` = `com.pathlogic.core` (all configs)
- [ ] Runner.entitlements: `aps-environment` = `production`
- [ ] RunnerDebug.entitlements: unchanged (for local dev)

**Signing Settings by Config:**

| Config | CODE_SIGN_STYLE | CODE_SIGN_IDENTITY | PROVISIONING_PROFILE_SPECIFIER |
|--------|----------------|-------------------|-------------------------------|
| Debug | Automatic | Apple Development | (managed by Xcode) |
| Release | Manual | Apple Distribution | `tweb-pathlogic` |
| Profile | Manual | Apple Distribution | `tweb-pathlogic` |

**Note:** Debug uses automatic signing for local dev. Release/Profile use manual signing for TestFlight archives. This is the standard Apple pattern.

**Status:** ✅ Done

---

### US-05: Configure GitHub Secrets for CI/CD (Future)
**As a** developer,
**I want** GitHub Actions secrets updated with the TaggedWeb Inc. credentials,
**So that** automated builds and deployments work from CI.

**Acceptance Criteria:**
- [ ] `APP_STORE_CONNECT_API_KEY_KEY_ID` — new API key from org
- [ ] `APP_STORE_CONNECT_API_KEY_ISSUER_ID` — new issuer from org
- [ ] `APP_STORE_CONNECT_API_KEY_KEY` — new key content
- [ ] `MATCH_SSH_PRIVATE_KEY` — updated if match repo changes
- [ ] `MATCH_PASSWORD` — updated if needed
- [ ] `apple_id` in Appfile — org's Apple ID
- [ ] `team_id` in Appfile — `3AKM83DNCV`
- [ ] `itc_team_id` in Appfile — `3AKM83DNCV`

**Status:** Not started — manual deployment first

---

### US-06: Build and Archive IPA
**As a** developer,
**I want** a signed IPA built with the org's distribution certificate and provisioning profile,
**So that** I can upload it to TestFlight via Transporter.

**Acceptance Criteria:**
- [x] Archive passes in Xcode: Product → Archive
- [ ] Export IPA: Distribute App → App Store Connect → Export
- [ ] IPA is signed with `iPhone Distribution: TaggedWeb Inc. (3AKM83DNCV)`
- [ ] IPA output saved to disk

**Status:** Archive ✅ Done | Export ❌ Pending

---

### US-07: Upload to TestFlight via Transporter
**As a** developer,
**I want** to upload the signed IPA to TestFlight using Transporter,
**So that** the first build of PathLogic is available for beta testing under the TaggedWeb Inc. account.

**Acceptance Criteria:**
- [ ] IPA uploaded via Transporter (or `xcrun altool`)
- [ ] Build appears in App Store Connect → TestFlight
- [ ] Build status: "Processing" → "Ready to Test"
- [ ] Internal testers can install the build

**Status:** Blocked by US-06

---

### US-08: Update Fastlane Configuration (Future CI/CD)
**As a** developer,
**I want** Fastlane updated with the org's signing configuration,
**So that** automated deployments work correctly.

**Acceptance Criteria:**
- [ ] `app_config.json` updated with new team IDs
- [ ] `Matchfile` points to correct cert repo
- [ ] `Appfile` has correct org Apple ID and team IDs
- [ ] `Fastfile` lanes work with org credentials

**Status:** Not started

---

## Files Changed in Migration

| File | Changes |
|------|---------|
| `ios/Runner.xcodeproj/project.pbxproj` | Team ID, bundle ID, signing settings |
| `ios/Runner/Runner.entitlements` | `aps-environment` → `production` |
| `.github/app_config.json` | Team IDs (when updating for CI) |
| `.github/workflows/ios_deploy.yml` | No changes needed (reads from config) |

---

## Blockers

1. **Automatic signing** — Need to register at least one device UDID under TaggedWeb Inc. (US-01)
2. **Keychain trust** — Distribution cert needs "Use System Defaults" trust (not "Always Trust")
3. **Keychain ACL** — `codesign` needs permission to access the private key without constant popups

---

## Next Steps

### Immediate (Get to TestFlight)
1. Export IPA from Xcode: Distribute App → App Store Connect → Export
2. Upload via Transporter

### To Enable Automatic Signing (Local Dev)
1. Register Mac UDID at [developer.apple.com/account/resources/devices](https://developer.apple.com/account/resources/devices)
2. Register test device UDIDs
3. In Xcode: Debug tab → "Automatically manage signing" → TaggedWeb Inc.
4. Build and run on physical device — automatic signing should work

### Future (CI/CD)
1. Update `app_config.json` with new team IDs
2. Generate App Store Connect API key
3. Update GitHub Secrets
4. Update Matchfile/Appfile/Fastfile
