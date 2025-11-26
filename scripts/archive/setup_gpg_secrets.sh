#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <gpg-key-id> [passphrase]" >&2
  echo "Example: $0 12345678ABCDEFGH" >&2
  echo "Example: $0 12345678ABCDEFGH mypassphrase" >&2
  echo "" >&2
  echo "This script sets up GPG secrets for automated release signing." >&2
  echo "It requires 'gh' CLI to be installed and authenticated." >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

GPG_KEY_ID="$1"
PASSPHRASE="${2:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: 'gh' CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: Not authenticated with GitHub. Run 'gh auth login' first." >&2
  exit 1
fi

echo "Setting up GPG secrets for key: $GPG_KEY_ID"

# Export GPG private key
if ! gpg --armor --export-secret-keys "$GPG_KEY_ID" > /tmp/gpg_private_key.asc 2>/dev/null; then
  echo "Error: Failed to export GPG private key $GPG_KEY_ID" >&2
  echo "Make sure the key exists in your keyring: gpg --list-secret-keys" >&2
  exit 1
fi

echo "Setting repository secrets..."

# Set GPG_SIGN
echo "true" | gh secret set GPG_SIGN
echo "✓ Set GPG_SIGN=true"

# Set GPG_PRIVATE_KEY
gh secret set GPG_PRIVATE_KEY < /tmp/gpg_private_key.asc
echo "✓ Set GPG_PRIVATE_KEY"

# Set GPG_PASSPHRASE if provided
if [[ -n "$PASSPHRASE" ]]; then
  echo "$PASSPHRASE" | gh secret set GPG_PASSPHRASE
  echo "✓ Set GPG_PASSPHRASE"
else
  echo "⚠ GPG_PASSPHRASE not set. You may need to set it manually:"
  echo "  echo 'your-passphrase' | gh secret set GPG_PASSPHRASE"
fi

# Cleanup
rm -f /tmp/gpg_private_key.asc

echo ""
echo "✅ GPG secrets configured successfully!"
echo "Next release will be automatically signed with key $GPG_KEY_ID"
echo ""
echo "To test:"
echo "  1. Update VERSION file"
echo "  2. git commit -am 'chore(release): bump version'"
echo "  3. git push"
echo "  4. Check Actions tab for release workflow"
