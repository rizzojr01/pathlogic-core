# Project Configuration Reference

Use this file to replicate the CI/CD setup for another repo.

---

## 📦 App Configurations

### PlCore
| Field | Value |
|-------|-------|
| Bundle ID | `com.taggedweb.pathlogic` |
| Team ID | `M26N2KSNVL` |
| App Store Connect Team ID | `M26N2KSNVL` |
| iTunes Connect Team ID | `M26N2KSNVL` |
| Display Name | `PlCore` |

### PlPro
| Field | Value |
|-------|-------|
| Bundle ID | `com.taggedweb.pathlogic-pro` |
| Team ID | `M26N2KSNVL` |
| App Store Connect Team ID | `M26N2KSNVL` |
| iTunes Connect Team ID | `M26N2KSNVL` |
| Display Name | `PlPro` |

---

## 🔐 GitHub Secrets to Add

Go to **Settings → Secrets and variables → Actions**

| Secret Name | Value |
|-------------|-------|
| `APPLE_ID` | `YOUR_APPLE_DEV_EMAIL` |
| `MATCH_SSH_PRIVATE_KEY` | Content of `~/.ssh/match_deploy_key` (private key file) |
| `MATCH_PASSWORD` | Password used for match encryption |
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | From App Store Connect → Keys |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | From App Store Connect → Keys |
| `APP_STORE_CONNECT_API_KEY_KEY` | Content of `.p8` file from App Store Connect |

---

## 🔑 SSH Key Info

Generated with:
```bash
ssh-keygen -t ed25519 -C "github-actions@smartsense" -f ~/.ssh/match_deploy_key
```

| File | Path | Used For |
|------|------|----------|
| Private key | `~/.ssh/match_deploy_key` | `MATCH_SSH_PRIVATE_KEY` secret |
| Public key | `~/.ssh/match_deploy_key.pub` | Deploy key on `rizzojr01/ios-certificates` repo |

---

## 📁 Repositories

| Repo | Purpose | Visibility |
|------|---------|------------|
| `rizzojr01/smartsense-app` | Main app repo with workflow | Private |
| `rizzojr01/ios-certificates` | Fastlane Match certificates storage | Private |

---

## 📂 GitHub Actions Files

### `.github/workflows/ios_deploy.yml`
- Name: `iOS TestFlight Deployment`
- Trigger: `workflow_dispatch` (manual)
- Flutter version: `3.41.9`
- Ruby version: `3.2`

### `.github/app_config.json`
Contains both app configurations. Update this file when adding new apps.

### `.github/SECRETS_SETUP.md`
Detailed guide on where to get each secret.

---

## 🛠 Local Setup Commands

```bash
# Install Ruby 3.2
brew install ruby@3.2

# Add to PATH
export PATH="/opt/homebrew/opt/ruby@3.2/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/3.2.0/bin:$PATH"

# Install gems
cd ios
bundle install

# Add SSH key to agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/match_deploy_key

# Generate certificates (first time)
MATCH_PASSWORD="your-password" \
FASTLANE_USER="your-apple-email" \
FASTLANE_PASSWORD="your-app-specific-password" \
bundle exec fastlane match appstore \
  --app_identifier com.taggedweb.pathlogic \
  --team_id M26N2KSNVL

# For PlPro (when needed)
MATCH_PASSWORD="your-password" \
FASTLANE_USER="your-apple-email" \
FASTLANE_PASSWORD="your-app-specific-password" \
bundle exec fastlane match appstore \
  --app_identifier com.taggedweb.pathlogic-pro \
  --team_id M26N2KSNVL
```

---

## 🚀 Replicating for Another Repo

To set this up for a new repo:

1. **Copy the `.github/` folder** to the new repo
2. **Update `.github/app_config.json`** with correct bundle IDs
3. **Update `.github/workflows/ios_deploy.yml`**:
   - Change match git URL to the new certificates repo
4. **Create a new certificates repo** (e.g., `rizzojr01/new-app-certs`)
5. **Generate new SSH key** and add as deploy key
6. **Add all 6 GitHub Secrets** to the new repo
7. **Run match locally** to generate certificates

---

## ⚠️ Security Warning

- **NEVER commit real secrets** to version control
- Keep `MATCH_PASSWORD`, SSH private keys, and API keys secure
- Rotate keys periodically
- Use a password manager to store credentials
