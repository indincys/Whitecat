#!/bin/zsh
set -euo pipefail

# sparkle_key_manager.sh — Manage Sparkle EdDSA signing key in macOS login Keychain.
#
# Usage:
#   sparkle_key_manager.sh import [--from-file <path>]   Import key into Keychain
#   sparkle_key_manager.sh import --generate              Generate new key pair and import
#   sparkle_key_manager.sh get-private                    Print private key from Keychain
#   sparkle_key_manager.sh get-public                     Print public key (derived from private)
#   sparkle_key_manager.sh write-plist [<plist-path>]     Write SUPublicEDKey into Info.plist.template
#   sparkle_key_manager.sh delete                         Remove key from Keychain

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN_SERVICE="Whitecat Sparkle EdDSA"
KEYCHAIN_ACCOUNT="sparkle-eddsa-private-key"
INFO_TEMPLATE="$ROOT_DIR/Configs/Info.plist.template"
GENERATE_KEYS_TOOL="$ROOT_DIR/Vendor/SparkleTools/generate_keys"

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

keychain_has_key() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1
}

keychain_get_private() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null \
    || fail "Sparkle private key not found in Keychain. Run: sparkle_key_manager.sh import"
}

# Derive Ed25519 public key from the private key using Swift + CryptoKit.
derive_public_key() {
  local private_b64="$1"
  swift - "$private_b64" <<'SWIFT_EOF'
import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count > 1,
      let keyData = Data(base64Encoded: args[1]) else {
    fputs("ERROR: invalid base64 private key\n", stderr)
    exit(1)
}

// Sparkle stores the full 64-byte Ed25519 key (32-byte seed + 32-byte public key).
// CryptoKit expects the 32-byte seed only.
let seed: Data
if keyData.count == 64 {
    seed = keyData.prefix(32)
} else if keyData.count == 32 {
    seed = keyData
} else {
    fputs("ERROR: unexpected key length \(keyData.count); expected 32 or 64 bytes\n", stderr)
    exit(1)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let publicB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
    print(publicB64, terminator: "")
} catch {
    fputs("ERROR: \(error)\n", stderr)
    exit(1)
}
SWIFT_EOF
}

cmd_import() {
  local private_key=""

  if [[ "${1:-}" == "--generate" ]]; then
    [[ -x "$GENERATE_KEYS_TOOL" ]] || fail "Sparkle generate_keys not found at $GENERATE_KEYS_TOOL"

    echo "Generating new Sparkle EdDSA key pair..."
    local gen_output
    gen_output="$("$GENERATE_KEYS_TOOL" -p 2>&1)"

    # generate_keys -p prints the private key (base64) then the public key
    private_key="$(echo "$gen_output" | head -n 1)"
    local public_key
    public_key="$(echo "$gen_output" | tail -n 1)"

    if [[ -z "$private_key" ]]; then
      # Fallback: generate_keys may output differently, try parsing
      fail "Failed to parse generate_keys output. Run generate_keys manually and use --from-file."
    fi

    echo "Public key: $public_key"

  elif [[ "${1:-}" == "--from-file" ]]; then
    local key_file="${2:-}"
    [[ -n "$key_file" ]] || fail "Usage: sparkle_key_manager.sh import --from-file <path>"
    [[ -f "$key_file" ]] || fail "Key file not found: $key_file"
    private_key="$(cat "$key_file" | tr -d '[:space:]')"

  elif [[ "${1:-}" == "--from-stdin" ]]; then
    echo "Paste the Sparkle private key (base64), then press Enter:"
    read -r private_key
    private_key="$(echo "$private_key" | tr -d '[:space:]')"

  else
    # Try default file location
    local default_path="${HOME}/.config/whitecat/sparkle_private_key"
    if [[ -f "$default_path" ]]; then
      private_key="$(cat "$default_path" | tr -d '[:space:]')"
      echo "Importing from default location: $default_path"
    else
      cat <<'EOF'
Usage:
  sparkle_key_manager.sh import --from-file <path>
  sparkle_key_manager.sh import --from-stdin
  sparkle_key_manager.sh import --generate
EOF
      exit 1
    fi
  fi

  [[ -n "$private_key" ]] || fail "Private key is empty."

  # Validate the key by deriving the public key
  local public_key
  public_key="$(derive_public_key "$private_key")" || fail "Invalid private key data."
  echo "Derived public key: $public_key"

  # Delete existing key if present
  if keychain_has_key; then
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1 || true
    echo "Replaced existing key in Keychain."
  fi

  # Store in login Keychain
  security add-generic-password \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w "$private_key" \
    -T "" \
    -U

  echo "Private key stored in login Keychain (service: '$KEYCHAIN_SERVICE')."
  echo ""
  echo "To update Info.plist.template with the public key, run:"
  echo "  ./Scripts/sparkle_key_manager.sh write-plist"
}

cmd_get_private() {
  keychain_get_private
}

cmd_get_public() {
  local private_key
  private_key="$(keychain_get_private)"
  derive_public_key "$private_key"
}

cmd_write_plist() {
  local target="${1:-$INFO_TEMPLATE}"
  [[ -f "$target" ]] || fail "Plist file not found: $target"

  local private_key public_key
  private_key="$(keychain_get_private)"
  public_key="$(derive_public_key "$private_key")"

  if grep -q '<key>SUPublicEDKey</key>' "$target"; then
    # Replace existing SUPublicEDKey value
    sed -i '' "/<key>SUPublicEDKey<\/key>/{n;s|<string>.*</string>|<string>${public_key}</string>|;}" "$target"
    echo "Updated SUPublicEDKey in $target"
  else
    # Insert before closing </dict>
    sed -i '' "/<\/dict>/i\\
	<key>SUPublicEDKey</key>\\
	<string>${public_key}</string>
" "$target"
    echo "Added SUPublicEDKey to $target"
  fi

  echo "SUPublicEDKey = $public_key"
}

cmd_delete() {
  if keychain_has_key; then
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1
    echo "Sparkle private key removed from Keychain."
  else
    echo "No Sparkle key found in Keychain."
  fi
}

case "${1:-}" in
  import)
    shift
    cmd_import "$@"
    ;;
  get-private)
    cmd_get_private
    ;;
  get-public)
    cmd_get_public
    ;;
  write-plist)
    shift
    cmd_write_plist "$@"
    ;;
  delete)
    cmd_delete
    ;;
  *)
    cat <<'EOF'
sparkle_key_manager.sh — Manage Sparkle EdDSA signing key in macOS login Keychain

Commands:
  import --from-file <path>   Import private key from file into Keychain
  import --from-stdin         Import private key from stdin
  import --generate           Generate new key pair and import into Keychain
  get-private                 Print private key (base64) from Keychain
  get-public                  Derive and print public key (base64)
  write-plist [<path>]        Write SUPublicEDKey into Info.plist.template
  delete                      Remove key from Keychain
EOF
    exit 1
    ;;
esac
