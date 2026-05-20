# GitHub Actions Secrets Setup Guide

This document lists all the secrets required for the iOS CI/CD pipeline and where to obtain them.

---

## 📋 Required Secrets Summary

You need to add **7 secrets** to your GitHub repository:

| # | Secret Name | Priority | Source |
|---|-------------|----------|--------|
| 1 | `APPLE_ID` | Required | Your Apple Developer account |
| 2 | `APP_STORE_CONNECT_API_KEY_KEY_ID` | Required | App Store Connect |
| 3 | `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Required | App Store Connect |
| 4 | `APP_STORE_CONNECT_API_KEY_KEY` | Required | App Store Connect |
| 5 | `MATCH_SSH_PRIVATE_KEY` | Required | Generate locally |
| 6 | `MATCH_PASSWORD` | Required | Create yourself |
| 7 | `FASTLANE_PASSWORD` | Optional fallback | appleid.apple.com |

---

## 🔐 1. APPLE_ID

**What it is:** Your Apple Developer email address

**How to get it:**
1. You already have this - it's the email you use to log into Apple Developer
2. Example: `yourname@company.com`

**Add to GitHub:**
- Go to Settings → Secrets and variables → Actions
- Click "New repository secret"
- Name: `APPLE_ID`
- Value: your Apple Developer email

---

## 🔐 2. APP_STORE_CONNECT_API_KEY_KEY_ID

**What it is:** The identifier for your App Store Connect API key

**How to get it:**
1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Click your name (top right) → "User Access"
3. Go to the "Keys" tab
4. Click the "+" button to create a new key
5. Name: `GitHub Actions CI/CD`
6. Access: Select **App Manager** or **Admin**
7. Click "Generate"
8. **Important:** The Key ID is shown - copy it (e.g., `ABC123DEF4`)

**Add to GitHub:**
- Name: `APP_STORE_CONNECT_API_KEY_KEY_ID`
- Value: The Key ID you just copied

---

## 🔐 3. APP_STORE_CONNECT_API_KEY_ISSUER_ID

**What it is:** The issuer identifier for your API key

**How to get it:**
1. Same page as above (App Store Connect → User Access → Keys)
2. Look at the top of the page
3. You'll see "Issuer ID" with a value like `12345678-1234-1234-1234-123456789abc`
4. Copy this value

**Add to GitHub:**
- Name: `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- Value: The Issuer ID you copied

---

## 🔐 4. APP_STORE_CONNECT_API_KEY_KEY

**What it is:** The private key content (the actual `.p8` file content)

**How to get it:**
1. Right after creating the key in App Store Connect (see step 2)
2. Click "Download API Key"
3. **⚠️ CRITICAL:** You can only download this ONCE! Save it securely.
4. Open the downloaded `.p8` file in a text editor
5. Copy the entire content including:
   ```
   -----BEGIN EC PRIVATE KEY-----
   ... (key content) ...
   -----END EC PRIVATE KEY-----
   ```

**Add to GitHub:**
- Name: `APP_STORE_CONNECT_API_KEY_KEY`
- Value: The entire private key content from the `.p8` file

---

## 🔐 5. MATCH_SSH_PRIVATE_KEY

**What it is:** SSH private key for accessing your code signing certificates repository

**How to generate it:**

```bash
# Generate a new SSH key (run this on your local machine)
ssh-keygen -t ed25519 -C "github-actions@your-org.com" -f match_deploy_key

# This creates two files:
# - match_deploy_key (private key - KEEP SECRET)
# - match_deploy_key.pub (public key - can be shared)
```

**Add the public key to your certificates repository:**
1. Create a new private GitHub repository (e.g., `your-org/ios-certificates`)
2. Go to Settings → Deploy keys
3. Click "Add deploy key"
4. Title: `GitHub Actions Match`
5. Key: Paste the content of `match_deploy_key.pub`
6. Check "Allow write access"
7. Click "Add key"

**Add to GitHub Secrets:**
- Name: `MATCH_SSH_PRIVATE_KEY`
- Value: The entire content of `match_deploy_key` (private key file)

---

## 🔐 6. MATCH_PASSWORD

**What it is:** Password to encrypt/decrypt your code signing certificates

**How to create it:**
1. This is just a password you create yourself
2. Make it strong and unique (e.g., a random 20+ character string)
3. You'll use this same password when running `fastlane match` locally

**Example:**
```
MyStr0ng!P@ssw0rd#2024
```

**Add to GitHub:**
- Name: `MATCH_PASSWORD`
- Value: The password you created

**⚠️ Important:** Save this password in a password manager - you'll need it for local development too!

---

## 🔐 7. FASTLANE_PASSWORD (Optional Fallback)

**What it is:** App-specific password for Apple ID (NOT your regular password)

**When to use:** Only if you're NOT using App Store Connect API Key method

**How to get it:**
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in with your Apple ID
3. Scroll down to "App-Specific Passwords"
4. Click "Generate an app-specific password"
5. Label: `GitHub Actions CI/CD`
6. Copy the generated password (looks like: `abcd-efgh-ijkl-mnop`)

**Add to GitHub:**
- Name: `FASTLANE_PASSWORD`
- Value: The app-specific password

**Note:** We recommend using the App Store Connect API Key method (secrets 2-4) instead of this, as it's more secure.

---

## 🚀 Quick Setup Checklist

- [ ] Created App Store Connect API Key
- [ ] Downloaded and saved the `.p8` file
- [ ] Copied Key ID, Issuer ID, and private key content
- [ ] Generated SSH key pair for match
- [ ] Added public key to certificates repository
- [ ] Created private certificates repository on GitHub
- [ ] Created strong password for MATCH_PASSWORD
- [ ] Added all 6 (or 7) secrets to GitHub repository

---

## 📍 Where to Add Secrets in GitHub

1. Go to your GitHub repository
2. Click **Settings** (top navigation)
3. In left sidebar, click **Secrets and variables** → **Actions**
4. Click **"New repository secret"**
5. Add each secret one by one

---

## ⚠️ Security Notes

1. **Never commit secrets** to your repository
2. **Never share the private key** (`.p8` file or SSH private key)
3. **Use a password manager** to store MATCH_PASSWORD
4. **Rotate keys periodically** for security
5. **The App Store Connect API Key can only be downloaded once** - save it immediately!

---

## 🔧 Next Steps After Adding Secrets

1. Initialize fastlane match locally:
   ```bash
   cd ios
   bundle install
   bundle exec fastlane match init
   ```

2. Generate certificates for PlCore:
   ```bash
   bundle exec fastlane match appstore \
     --app_identifier com.taggedweb.pathlogic \
     --team_id M26N2KSNVL
   ```

3. Generate certificates for PlPro (when ready):
   ```bash
   bundle exec fastlane match appstore \
     --app_identifier com.taggedweb.pathlogic-pro \
     --team_id M26N2KSNVL
   ```

4. Run the GitHub Action from the Actions tab!

---

## 🆘 Troubleshooting

**"Invalid credentials" error:**
- Check that APP_STORE_CONNECT_API_KEY_KEY_ID is correct
- Verify the API key hasn't expired or been revoked

**"SSH authentication failed" error:**
- Verify MATCH_SSH_PRIVATE_KEY is the full private key content
- Check that the public key was added to the certificates repo

**"Certificate not found" error:**
- Run fastlane match locally first to generate certificates
- Ensure MATCH_PASSWORD is the same as what you used locally
