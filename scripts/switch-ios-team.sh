#!/usr/bin/env bash
# Regenerate iOS signing certs on the current TaggedWeb Inc. team (3AKM83DNCV).
# Idempotent — safe to re-run. Reads .p8 from repo root or ~/.apple-keys/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$REPO_ROOT/ios"

# --- API key credentials (App Store Connect) ---
export APP_STORE_CONNECT_API_KEY_KEY_ID="F7GW39TWLB"
export APP_STORE_CONNECT_API_KEY_ISSUER_ID="d347aa1f-1d57-4da3-9d19-6563935a853a"

# --- Match repo encryption passphrase (from .env.match, gitignored) ---
if [[ -f "$REPO_ROOT/.env.match" ]]; then
  set -a; . "$REPO_ROOT/.env.match"; set +a
fi
if [[ -z "${MATCH_PASSWORD:-}" ]]; then
  echo "ERROR: MATCH_PASSWORD not set. Create $REPO_ROOT/.env.match with MATCH_PASSWORD=..."
  exit 1
fi

P8_CANDIDATES=(
  "$REPO_ROOT/AuthKey_F7GW39TWLB.p8"
  "$HOME/.apple-keys/AuthKey_F7GW39TWLB.p8"
)
P8_PATH=""
for p in "${P8_CANDIDATES[@]}"; do
  [[ -f "$p" ]] && P8_PATH="$p" && break
done
if [[ -z "$P8_PATH" ]]; then
  echo "ERROR: AuthKey_F7GW39TWLB.p8 not found. Looked in:"
  printf '  %s\n' "${P8_CANDIDATES[@]}"
  exit 1
fi
export APP_STORE_CONNECT_API_KEY_KEY="$(cat "$P8_PATH")"
echo "Using .p8 from: $P8_PATH"

# --- Ruby (Homebrew 3.x — system Ruby 2.6 is too old for fastlane) ---
if [[ -d /opt/homebrew/opt/ruby/bin ]]; then
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
fi
echo "Ruby: $(ruby --version)"

# --- Match: generate new team's certs on the freshly-wiped repo ---
cd "$IOS_DIR"
bundle install

echo ">>> Generating fresh distribution certs on team 3AKM83DNCV..."
bundle exec fastlane sync_certs

echo
echo "✅ Done. Match repo now has new team's certs."
echo "Next: commit + push any local changes, then trigger GitHub Action."
