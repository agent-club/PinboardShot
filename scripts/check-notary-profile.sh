#!/bin/zsh
set -euo pipefail

notary_profile="${1:-${PINBOARDSHOT_NOTARY_PROFILE:-PinboardShot-notary}}"
check_dir="$(mktemp -d /private/tmp/pinboardshot-notary-check.XXXXXX)"
trap '[[ -d "$check_dir" ]] && /usr/bin/find "$check_dir" -depth -delete' EXIT

# Keychain lookup failures also occur in restricted execution contexts; they do not prove absence or expiry.
if ! xcrun notarytool history --keychain-profile "$notary_profile" --output-format json \
    > "$check_dir/history.json" 2> "$check_dir/error.txt"; then
  echo "Cannot access the configured notarization profile in this execution context." >&2
  echo "Verify approved host and Keychain access before diagnosing the profile as missing or expired." >&2
  echo "Do not recreate credentials based only on this lookup failure." >&2
  exit 78
fi

if ! python3 - "$check_dir/history.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        response = json.load(stream)
    confirmed = isinstance(response, dict) and "history" in response and isinstance(response["history"], list)
except (OSError, json.JSONDecodeError):
    confirmed = False
sys.exit(0 if confirmed else 1)
PY
then
  echo "Notarization access check did not return a confirmed history response." >&2
  exit 78
fi

echo "Notarization profile access verified in this execution context."
