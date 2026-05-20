# GitHub Actions Secrets Setup Guide

This document lists all the secrets required for the iOS CI/CD pipeline and where to obtain them.

---

## 📋 Required Secrets Summary

You need to add **4 secrets** to your GitHub repository:

| # | Secret Name | Priority | Source |
|---|-------------|----------|--------|
| 1 | `APPLE_ID` | Required | Your Apple Developer account |
| 2 | `APP_STORE_CONNECT_API_KEY_KEY_ID` | Required | App Store Connect |
| 3 | `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Required | App Store Connect |
| 4 | `APP_STORE_CONNECT_API_KEY_KEY` | Required | App Store Connect |

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

## 🚀 Quick Setup Checklist

- [ ] Created App Store Connect API Key
- [ ] Downloaded and saved the `.p8` file
- [ ] Copied Key ID, Issuer ID, and private key content
- [ ] Added all 4 secrets to GitHub repository

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
2. **Never share the API private key** (`.p8` file)
3. **Rotate keys periodically** for security
4. **The App Store Connect API Key can only be downloaded once** - save it immediately!

---

## 🔧 Next Steps After Adding Secrets

1. Verify all 4 secrets are added in GitHub Settings → Secrets → Actions

2. Run the GitHub Action from the Actions tab:
   - Select **iOS TestFlight Deployment**
   - Choose the app (`plcore` or `plpro`)
   - Choose environment (`testflight`)
   - Click **Run workflow**

The workflow will use Xcode's automatic provisioning with the App Store Connect API Key for code signing — no need for fastlane match or certificates repo.

---

## 🆘 Troubleshooting

**"Invalid credentials" error:**
- Check that APP_STORE_CONNECT_API_KEY_KEY_ID is correct
- Verify the API key hasn't expired or been revoked

**"Code signing" errors:**
- Ensure the app exists in App Store Connect with the correct bundle ID
- Verify that automatic provisioning is enabled for the App ID in App Store Connect
- Make sure the API key has **App Manager** role or higher

**"Provisioning profile" errors:**
- Go to App Store Connect → Certificates, Identifiers & Profiles
- Ensure the bundle ID `com.taggedweb.pathlogic` (or `com.taggedweb.pathlogic-pro`) is registered
