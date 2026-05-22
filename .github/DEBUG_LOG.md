# CI/CD Debug Log

## Deployment issues in chronological order

| # | Issue | Approach | Result |
|---|-------|----------|--------|
| 1 | Dart SDK ^3.10.4 requires Flutter 3.29.2+ | Updated FLUTTER_VERSION to 3.41.9 (matches .fvmrc) | ✅ |
| 2 | SSH authentication failed for certificates repo | Generated SSH key pair + deploy key on ios-certificates repo + MATCH_SSH_PRIVATE_KEY secret | ✅ |
| 3 | `your-org/ios-certificates` repo not found | Updated Matchfile URL to `rizzojr01/ios-certificates` | ✅ |
| 4 | No code signing identity in readonly mode | Ran `fastlane match appstore` locally to generate + push certs | ✅ |
| 5 | `No Accounts` error - automatic signing needs Apple ID on CI | Set CODE_SIGN_STYLE=Manual via xcargs | ❌ |
| 6 | `requires a provisioning profile` - manual signing needs specifier | Added PROVISIONING_PROFILE_SPECIFIER in xcargs | ❌ |
| 7 | RunnerTests looking for iOS Development certificate | Added `update_code_signing_settings` for RunnerTests target | ❌ |
| 8 | api_key `invalid curve name` on Ruby 3.2.11/OpenSSL | Removed `app_store_connect_api_key` action, rely on env vars auto-detection | ✅ |
| 9 | `update_code_signing_settings` without profile leaves Xcode clueless | Added back team_id + profile_name + targets + bundle_identifier | 🔄 |
| 10 | `build_app` missing export options | Added export_method + export_options.provisioningProfiles + destination | 🔄 |
| 11 | upload_to_testflight might need app_identifier | TBD if needed: add `app_identifier: app_identifier` back | ⏳ |
