# iOS TestFlight Deployment Guide - GitHub Actions & fastlane

Based on official documentation from GitHub, fastlane, and industry best practices.

## Overview

This guide covers the exact setup required to deploy iOS apps to TestFlight using GitHub Actions and fastlane, based on official documentation.

## Prerequisites

### 1. Apple Developer Account
- Apple Developer Program membership ($99/year)
- App Store Connect access
- Team ID (e.g., `M26N2KSNVL`)

### 2. App Store Connect API Key (Recommended)

The **App Store Connect API Key** is the preferred authentication method:
- Uses official App Store Connect API
- No need for 2FA
- Better performance than Apple ID
- Required for CI/CD automation

**How to create:**
1. Go to App Store Connect → Users and Access → Keys
2. Click "Request Access" if needed
3. Click the "+" button to create a new key
4. Name it (e.g., "GitHub Actions CI")
5. Select role: "App Manager" or "Admin"
6. Download the `.p8` file (only available once!)
7. Note the Key ID and Issuer ID

## Required GitHub Secrets

Based on GitHub's official documentation for code signing:

### Method A: Using fastlane match (Recommended)

```
MATCH_PASSWORD                    # Password for match encryption
MATCH_SSH_PRIVATE_KEY            # SSH key for accessing certificates repo
APPLE_ID                         # Your Apple ID email
APP_STORE_CONNECT_API_KEY_KEY_ID # API Key ID (e.g., D83848D23)
APP_STORE_CONNECT_API_KEY_ISSUER_ID # Issuer ID from App Store Connect
APP_STORE_CONNECT_API_KEY_KEY    # Contents of the .p8 file
```

### Method B: Manual Certificate Management

```
BUILD_CERTIFICATE_BASE64         # Base64-encoded .p12 certificate
P12_PASSWORD                     # Certificate password
BUILD_PROVISION_PROFILE_BASE64   # Base64-encoded .mobileprovision file
KEYCHAIN_PASSWORD                # Random password for temporary keychain
```

**Convert files to Base64:**
```bash
base64 -i Certificate.p12 | pbcopy
base64 -i ProvisioningProfile.mobileprovision | pbcopy
```

## Workflow Setup (Official GitHub Approach)

### Basic Workflow Structure

```yaml
name: iOS TestFlight Deployment

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: macos-latest  # or macos-15 for M1/M2
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
      
      - name: Build and Deploy
        run: fastlane beta
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
```

### Complete Official Example

Based on [GitHub's documentation](https://docs.github.com/en/actions/use-cases-and-examples/deploying/installing-an-apple-certificate-on-macos-runners-for-xcode-development):

```yaml
name: App build
on: push

jobs:
  build_with_signing:
    runs-on: macos-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6
        
      - name: Install the Apple certificate and provisioning profile
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          BUILD_PROVISION_PROFILE_BASE64: ${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # create variables
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db

          # import certificate and provisioning profile from secrets
          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH
          echo -n "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode -o $PP_PATH

          # create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          # import certificate to keychain
          security import $CERTIFICATE_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

          # apply provisioning profile
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles
          
      - name: Build app
        run: |
          xcodebuild -scheme MyApp -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath $RUNNER_TEMP/MyApp.xcarchive archive
          
      - name: Clean up keychain
        if: ${{ always() }}
        run: |
          security delete-keychain $RUNNER_TEMP/app-signing.keychain-db
          rm ~/Library/MobileDevice/Provisioning\ Profiles/build_pp.mobileprovision
```

## fastlane Setup (Official Approach)

### 1. Gemfile

Create a `Gemfile` in the `ios/` directory:

```ruby
source 'https://rubygems.org'

gem 'fastlane'
```

### 2. Fastfile (Official Example)

Based on [fastlane's GitHub Actions integration docs](https://docs.fastlane.tools/best-practices/continuous-integration/github/):

```ruby
platform :ios do
  lane :beta do
    # CRITICAL: Creates temporary keychain for CI
    # Without this, the build could freeze and never finish
    setup_ci if ENV['CI']
    
    # Sync code signing certificates
    match(type: 'appstore')
    
    # Build the app
    build_app
    
    # Upload to TestFlight
    upload_to_testflight(
      skip_waiting_for_build_processing: true
    )
  end
end
```

### 3. Complete Fastfile with All Best Practices

```ruby
platform :ios do
  desc "Deploy to TestFlight"
  lane :deploy_testflight do
    # Setup CI environment
    setup_ci if ENV['CI']
    
    # Fetch certificates and provisioning profiles
    match(
      type: "appstore",
      readonly: true,
      verbose: true
    )
    
    # Update code signing settings
    update_code_signing_settings(
      use_automatic_signing: false,
      path: "Runner.xcodeproj",
      team_id: ENV['TEAM_ID'],
      profile_name: "match AppStore #{ENV['BUNDLE_ID']}",
      code_sign_identity: "Apple Distribution",
      targets: ["Runner"],
      bundle_identifier: ENV['BUNDLE_ID']
    )
    
    # Build the app
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          ENV['BUNDLE_ID'] => "match AppStore #{ENV['BUNDLE_ID']}"
        }
      },
      clean: true
    )
    
    # Upload to TestFlight
    upload_to_testflight(
      skip_waiting_for_build_processing: true,
      changelog: "New build deployed via GitHub Actions"
    )
  end
end
```

## Authentication Methods

### Method 1: App Store Connect API Key (Recommended)

```ruby
# In your Fastfile or as environment variables
api_key = app_store_connect_api_key(
  key_id: ENV['APP_STORE_CONNECT_API_KEY_KEY_ID'],
  issuer_id: ENV['APP_STORE_CONNECT_API_KEY_ISSUER_ID'],
  key_content: ENV['APP_STORE_CONNECT_API_KEY_KEY'],
  is_key_content_base64: false
)

upload_to_testflight(api_key: api_key)
```

### Method 2: Apple ID with 2FA (Not Recommended for CI)

**Issues:**
- Requires 2FA which is problematic in CI
- Session expires frequently
- Not suitable for automated deployments

## Runner Selection

### GitHub-Hosted Runners

| Runner | Architecture | Xcode | Use Case |
|--------|-------------|-------|----------|
| `macos-latest` | Intel | Latest stable | Standard builds |
| `macos-14` | Intel | Xcode 15.x | Specific Xcode version |
| `macos-15` | Apple Silicon (M1/M2) | Xcode 16.x | Faster builds |

**Note:** `macos-15` requires downloading iOS platform if not pre-installed:
```yaml
- name: Download iOS Platform
  run: sudo xcodebuild -downloadPlatform iOS
```

## Common Issues & Solutions

### 1. Code Signing Hangs

**Problem:** Build freezes at code signing step

**Solution:** 
- Use `setup_ci` in fastlane (creates temporary keychain)
- Ensure `MATCH_PASSWORD` is set correctly

### 2. Certificate Not Found

**Problem:** `There are no local code signing identities found`

**Solution:**
- Verify match password is correct
- Check that certificates are in the match repository
- Run `fastlane match development` locally first

### 3. Provisioning Profile Mismatch

**Problem:** Profile doesn't match bundle identifier

**Solution:**
- Verify bundle ID in Xcode matches App Store Connect
- Run `fastlane match` with correct app identifier

### 4. iOS Platform Not Installed

**Problem:** `iOS 18.2 is not installed`

**Solution:**
```yaml
- name: Download iOS Platform
  run: sudo xcodebuild -downloadPlatform iOS
```

### 5. 2FA Issues

**Problem:** Apple ID requires 2FA

**Solution:**
- Use App Store Connect API Key instead
- Never use Apple ID with 2FA in CI

## Security Best Practices

1. **Use Repository Secrets** - Never commit certificates or API keys
2. **Use match** - Store certificates in a separate private repository
3. **Temporary Keychains** - Always use `setup_ci` or manual keychain creation
4. **Clean Up** - Delete keychains and profiles after build
5. **API Keys** - Prefer App Store Connect API over Apple ID
6. **Read-only Match** - Use `readonly: true` in CI to prevent modifications

## Required Environment Variables

```bash
# Required for match
MATCH_PASSWORD=your_match_encryption_password

# Required for App Store Connect API
APP_STORE_CONNECT_API_KEY_KEY_ID=your_key_id
APP_STORE_CONNECT_API_KEY_ISSUER_ID=your_issuer_id
APP_STORE_CONNECT_API_KEY_KEY=-----BEGIN EC PRIVATE KEY-----
...
-----END EC PRIVATE KEY-----

# Optional
FASTLANE_SKIP_UPDATE_CHECK=true
FASTLANE_XCODEBUILD_SETTINGS_TIMEOUT=30
FASTLANE_XCODEBUILD_SETTINGS_RETRIES=3
```

## Resources

- [GitHub Actions iOS Code Signing](https://docs.github.com/en/actions/use-cases-and-examples/deploying/installing-an-apple-certificate-on-macos-runners-for-xcode-development)
- [fastlane GitHub Actions Integration](https://docs.fastlane.tools/best-practices/continuous-integration/github/)
- [fastlane upload_to_testflight](https://docs.fastlane.tools/actions/upload_to_testflight/)
- [fastlane match](https://docs.fastlane.tools/actions/match/)
- [App Store Connect API](https://docs.fastlane.tools/app-store-connect-api/)

## Summary

The exact setup for deploying to TestFlight via GitHub Actions:

1. ✅ Use `macos-latest` or `macos-15` runner
2. ✅ Use App Store Connect API Key (not Apple ID)
3. ✅ Use fastlane match for certificate management
4. ✅ Call `setup_ci` in Fastfile for CI environments
5. ✅ Use repository secrets for all sensitive data
6. ✅ Set `skip_waiting_for_build_processing: true` for faster CI
7. ✅ Clean up keychains after build

This approach is the officially recommended setup by both GitHub and fastlane.
