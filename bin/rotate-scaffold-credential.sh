#!/usr/bin/env bash
set -euo pipefail

# Rotate a JWT scaffold credential. Reads the new password interactively (never echoed, never in
# argv, never in shell history), generates a fresh random salt, and prints the two PL/SQL constants
# to paste into db/package_bodies/jwt_scaffold_auth_api.pkb.
#
# The password itself is deliberately never sent to the database: the digest is computed locally
# using the identical formula to jwt_scaffold_auth_api.password_digest, which is
#   sha256( utf8_bytes(password) || salt_bytes )
# Passing it through SQLcl as a literal would leave the plaintext in the shared pool.
#
# Scaffold-lifetime tooling. It retires with JWT_SCAFFOLD_AUTH_API.

usage() {
  cat >&2 <<'EOF'
Usage: bin/rotate-scaffold-credential.sh --user <ADMIN|USER1|USER2>

Prompts for the new password, then prints the salt and hash constants to paste into
db/package_bodies/jwt_scaffold_auth_api.pkb. Redeploy the package body afterwards.
EOF
}

TARGET_USER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      TARGET_USER="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${TARGET_USER}" ]]; then
  usage
  exit 2
fi

TARGET_USER="$(printf '%s' "${TARGET_USER}" | tr '[:lower:]' '[:upper:]')"

case "${TARGET_USER}" in
  ADMIN|USER1|USER2) ;;
  *)
    echo "[ERROR] Unknown scaffold user: ${TARGET_USER}" >&2
    usage
    exit 2
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "[ERROR] python3 not found on PATH" >&2
  exit 127
fi

echo "[INFO] Rotating scaffold credential for ${TARGET_USER}"

python3 - "${TARGET_USER}" <<'PY'
import getpass
import hashlib
import os
import sys

target = sys.argv[1]

first = getpass.getpass(f"New password for {target} (hidden): ")
if not first:
    print("[ERROR] Empty password refused", file=sys.stderr)
    sys.exit(2)
if len(first) < 16:
    print("[ERROR] Refusing a password under 16 characters", file=sys.stderr)
    sys.exit(2)

second = getpass.getpass("Confirm: ")
if first != second:
    print("[ERROR] Passwords did not match", file=sys.stderr)
    sys.exit(2)

salt = os.urandom(16)
# Identical to jwt_scaffold_auth_api.password_digest: sha256(utf8(password) || salt).
digest = hashlib.sha256(first.encode("utf-8") + salt).digest()

prefix = f"c_{target.lower()}"
print()
print(f"[INFO] Paste these two lines over the existing {target} constants in")
print("[INFO] db/package_bodies/jwt_scaffold_auth_api.pkb, then redeploy the package body:")
print()
print(f"  {prefix}_salt     constant raw(16)      := hextoraw('{salt.hex().upper()}');")
print(f"  {prefix}_hash     constant raw(32)      := hextoraw('{digest.hex().upper()}');")
print()
print("[INFO] Store the password itself in your password manager. It is not recoverable from these.")
PY
