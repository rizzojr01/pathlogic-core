# CI/CD Migration Checklist: Individual → Org Account

## Overview
- **Old Account:** Individual developer account
- **New Account:** TaggedWeb Inc. (Org)
- **Team ID:** `3AKM83DNCV`
- **Bundle ID:** `com.pathlogic.core`

---

## What You Have vs What You Need

### 1. Apple Developer Portal

| Item | Status | Notes |
|------|--------|-------|
| App ID for `com.pathlogic.core` | ❓ | Check if it exists under the org account |
| Distribution Certificate (Apple Distribution) | ❌ Need | Must be created under TaggedWeb Inc. (old cert won't work) |
| App Store Provisioning Profile | ❌ Need | Must be created for `com.pathlogic.core` under org |
| App Store Connect API Key | ❌ Need | For fastlane to upload to TestFlight |
| Push Notification enabled in App ID | ❓ | Verify in App IDs section |

### 2. GitHub Secrets

| Secret | Purpose | Status |
|--------|---------|--------|
| `MATCH_SSH_PRIVATE_KEY` | SSH key for certificates repo | ❌ Need to create and set |
| `MATCH_PASSWORD` | Encryption password for fastlane match | ❌ Need to set |
| `FASTLANE_PASSWORD` | Apple ID password for fastlane | ❌ Need to set (org Apple ID) |
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | API Key ID from App Store Connect | ❌ Need to create key first |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID from App Store Connect | ❌ Will get after key creation |
| `APP_STORE_CONNECT_API_KEY_KEY` | .p8 file content | ❌ Download after key creation |
| `APPLE_ID` | Org's Apple ID email | ❌ Need to set |

### 3. Code Signing (Certificates Repo)

| Item | Status | Notes |
|------|--------|-------|
| Private `ios-certificates` repo on GitHub | ❌ Need | Create under TaggedWeb org |
| Fastlane match initialized | ❌ Need | Run `fastlane match appstore` locally |
| Certificates stored encrypted in repo | ❌ Need | Happens after match init |

### 4. Local Configuration Files

| File | Status | What to Check |
|------|--------|---------------|
| `ios/Runner.xcodeproj/project.pbxproj` | ✅ Done | Team ID = `3AKM83DNCV` |
| `ios/ExportOptions.plist` | ✅ Done | Team ID = `3AKM83DNCV` |
| `.github/app_config.json` | ✅ Done | Team ID = `3AKM83DNCV`, Bundle ID = `com.pathlogic.core` |
| `ios/Runner/Runner.entitlements` | ✅ Done | `aps-environment` = `production` |
| `ios/fastlane/Matchfile` | ❌ Need Update | Change `git_url` to real certificates repo |
| `ios/fastlane/Appfile` | ✅ Done | Created dynamically in workflow |

### 5. GitHub Workflow

| Item | Status | Notes |
|------|--------|-------|
| Auto-deploy on push to main | ✅ Done | Added push trigger |
| Manual trigger option | ✅ Done | `workflow_dispatch` available |
| Flutter version | ✅ Done | `3.24.5` matches workflow |
| Secrets validation | ✅ Done | Checks before build |

---

## Step-by-Step Setup Order

### Step 1: Apple Developer Portal
1. [ ] Login to developer.apple.com with org account
2. [ ] Verify `com.pathlogic.core` App ID exists (create if not)
3. [ ] Enable Push Notifications capability on the App ID
4. [ ] Create Distribution Certificate (Apple Distribution type)
5. [ ] Create App Store Provisioning Profile
6. [ ] Create App Store Connect API Key (Users and Access → Integrations → Keys)

### Step 2: Local Machine
1. [ ] Download and install the distribution certificate
2. [ ] Download and install the provisioning profile
3. [ ] Fix certificate trust settings (Keychain → Use System Defaults)
4. [ ] Run `security find-identity -v -p codesigning` to verify

### Step 3: Create Certificates Repo
1. [ ] Create private repo `ios-certificates` on GitHub (under TaggedWeb org)
2. [ ] Create SSH key with access to the repo
3. [ ] Add SSH key to GitHub account

### Step 4: Initialize Fastlane Match
1. [ ] Run `cd ios` in terminal
2. [ ] Run `bundle exec fastlane match init`
3. [ ] Select "git" storage mode
4. [ ] Enter the certificates repo URL
5. [ ] Run `bundle exec fastlane match appstore`
6. [ ] Verify certificates are encrypted and pushed to repo

### Step 5: Set GitHub Secrets
1. [ ] Get SSH private key content: `cat ~/.ssh/id_rsa` (or your key)
2. [ ] Add to GitHub Secrets as `MATCH_SSH_PRIVATE_KEY`
3. [ ] Set `MATCH_PASSWORD` (the encryption password you used)
4. [ ] Set `FASTLANE_PASSWORD` (org Apple ID password)
5. [ ] Set `APPLE_ID` (org Apple ID email)
6. [ ] Get API Key ID, Issuer ID, and .p8 file from App Store Connect
7. [ ] Add them as `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_KEY`

### Step 6: Update Workflow File
1. [ ] Update `git_url` in Matchfile step to point to your real repo
2. [ ] Commit and push to test

---

## Quick Test

After setup, test with:
```bash
# Manual trigger
gh workflow run ios_deploy.yml -f app=plcore -f environment=testflight

# Or push to main
git push origin main
```

---

## Troubleshooting

| Issue | Likely Cause | Fix |
|-------|--------------|-----|
| "No signing certificate 'iOS Distribution' found" | Certificate not installed or wrong team | Re-install cert, verify team ID |
| "No profiles matching" | Provisioning profile not installed | Re-install profile |
| "Communication with Apple failed" | Automatic signing enabled | Ensure Manual signing in project |
| Match fails to clone | SSH key not set or wrong repo URL | Check `MATCH_SSH_PRIVATE_KEY` secret |
