# iOS CI/CD Deployment Setup

This repository is configured with GitHub Actions for automated iOS deployment to TestFlight and App Store.

## Features

- **Dropdown Selection**: Choose which app to deploy from a dropdown menu
- **Dynamic Configuration**: Bundle ID and Team ID are loaded from JSON configuration
- **Multi-App Support**: Supports deploying different apps from the same repository
- **Environment Selection**: Deploy to TestFlight or App Store
- **Version Control**: Optionally specify build version and number

## Configuration

### 1. App Configuration File

The file `.github/app_config.json` contains the configuration for all apps:

```json
{
  "apps": [
    {
      "id": "pathlogic",
      "name": "PathLogic",
      "bundle_id": "com.taggedweb.pathlogic",
      "team_id": "M26N2KSNVL",
      "app_store_connect_team_id": "M26N2KSNVL",
      "itc_team_id": "M26N2KSNVL",
      "provisioning_profile_specifier": "PathLogic Distribution",
      "display_name": "PathLogic"
    },
    {
      "id": "smartsense",
      "name": "SmartSense",
      "bundle_id": "PLACEHOLDER_BUNDLE_ID_2",
      "team_id": "PLACEHOLDER_TEAM_ID_2",
      ...
    }
  ]
}
```

**Update this file** with your actual app configurations before using the pipeline.

### 2. Required GitHub Secrets

Go to **Settings > Secrets and variables > Actions** and add the following secrets:

#### Apple Developer Account
- `APPLE_ID`: Your Apple Developer email address
- `FASTLANE_PASSWORD`: Your Apple ID password or app-specific password
- `APP_STORE_CONNECT_API_KEY_KEY_ID`: App Store Connect API Key ID
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`: App Store Connect API Key Issuer ID
- `APP_STORE_CONNECT_API_KEY_KEY`: App Store Connect API Key (private key content)

#### Code Signing
- `MATCH_SSH_PRIVATE_KEY`: SSH private key for accessing the certificates repository
- `MATCH_PASSWORD`: Password for encrypting/decrypting match certificates

### 3. Code Signing Setup (Fastlane Match)

Before using the pipeline, you need to set up code signing certificates:

1. **Create a private certificates repository** (e.g., `your-org/ios-certificates`)

2. **Generate an SSH key pair** for accessing the certificates:
   ```bash
   ssh-keygen -t ed25519 -C "github-actions@your-org.com" -f match_deploy_key
   ```

3. **Add the public key** to the certificates repository as a deploy key

4. **Add the private key** to GitHub Secrets as `MATCH_SSH_PRIVATE_KEY`

5. **Initialize match** (run locally once):
   ```bash
   cd ios
   bundle install
   bundle exec fastlane match init
   bundle exec fastlane match appstore --app_identifier com.taggedweb.pathlogic
   ```

### 4. App Store Connect API Key Setup

1. Go to [App Store Connect](https://appstoreconnect.apple.com/) > Users and Access > Keys
2. Create a new key with **App Manager** or **Admin** role
3. Download the private key (can only be downloaded once!)
4. Note the Key ID and Issuer ID
5. Add these to GitHub Secrets

## Usage

### Manual Deployment

1. Go to the **Actions** tab in GitHub
2. Select the **iOS TestFlight Deployment** workflow
3. Click **Run workflow**
4. Select from the dropdown:
   - **App**: Choose `pathlogic` or `smartsense`
   - **Build Version**: Optional version number (e.g., `1.0.0`)
   - **Build Number**: Optional build number (e.g., `1`)
   - **Environment**: `testflight` or `appstore`
   - **Release Notes**: Description of the build
5. Click **Run workflow**

### Automatic Deployment

You can also trigger deployment automatically on specific events:

```yaml
on:
  push:
    tags:
      - 'ios-v*'
```

## Workflow Steps

1. **Checkout**: Clones the repository
2. **Read Configuration**: Loads bundle ID and team ID from JSON
3. **Setup Environment**: Installs Flutter, Ruby, and dependencies
4. **Update Project**: Dynamically updates Xcode project with selected configuration
5. **Code Signing**: Retrieves certificates using fastlane match
6. **Build**: Creates an archive of the iOS app
7. **Deploy**: Uploads to TestFlight or App Store

## Troubleshooting

### Build Failures

Check the uploaded artifacts for build logs:
- Go to the failed workflow run
- Scroll to the bottom
- Download `ios-build-logs` artifact

### Code Signing Issues

1. Ensure certificates are properly set up in the match repository
2. Verify `MATCH_PASSWORD` is correct
3. Check that the SSH key has access to the certificates repository

### App Store Connect Issues

1. Verify API key has not expired
2. Ensure the app exists in App Store Connect with the correct bundle ID
3. Check that the API key has appropriate permissions

## Branch Considerations

Since you have two different apps in different branches:

1. **Update the JSON file** in each branch with the correct configuration
2. The workflow reads from the current branch's JSON file
3. Each branch should have its own app configuration

## Updating Configuration

To add a new app or update existing configuration:

1. Edit `.github/app_config.json`
2. Add the app `id` to the dropdown options in `.github/workflows/ios_deploy.yml`
3. Commit and push the changes

Example adding a new app:
```json
{
  "id": "newapp",
  "name": "New App",
  "bundle_id": "com.taggedweb.newapp",
  "team_id": "M26N2KSNVL",
  "app_store_connect_team_id": "M26N2KSNVL",
  "itc_team_id": "M26N2KSNVL",
  "provisioning_profile_specifier": "New App Distribution",
  "display_name": "New App"
}
```

Then update the workflow dropdown:
```yaml
options:
  - pathlogic
  - smartsense
  - newapp  # Add this
```
