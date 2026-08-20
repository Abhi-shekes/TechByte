#!/usr/bin/env bash
#
# Creates the release signing keystore and registers its fingerprints with
# Firebase.
#
# Run this yourself rather than letting a tool do it unattended. The keystore
# is the single most irreplaceable artefact in the project: lose it and you can
# never publish an update to the same Play listing again. Back it up somewhere
# that is not this repository.
set -euo pipefail

PROJECT_ID="techbyte-app"
APP_ID="1:213851361054:android:c408bd7f48b2de6a75c30f"

KEYSTORE="${1:-$HOME/techbyte-release.jks}"
ALIAS="techbyte"
ANDROID_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../android" && pwd)"
PROPERTIES="$ANDROID_DIR/key.properties"

if [[ -f "$KEYSTORE" ]]; then
  echo "✗ $KEYSTORE already exists. Refusing to overwrite it."
  echo "  Overwriting would permanently orphan any build already signed with it."
  exit 1
fi

echo "Creating release keystore at $KEYSTORE"
echo "Choose a strong password and store it in a password manager."
echo

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000

read -rsp "Re-enter the keystore password (for key.properties): " STORE_PASSWORD
echo
read -rsp "Re-enter the key password (blank if same as keystore): " KEY_PASSWORD
echo
KEY_PASSWORD="${KEY_PASSWORD:-$STORE_PASSWORD}"

# key.properties is gitignored; android/app/build.gradle.kts reads it and falls
# back to debug signing when absent.
cat > "$PROPERTIES" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$ALIAS
storeFile=$KEYSTORE
EOF
chmod 600 "$PROPERTIES"
echo "✓ Wrote $PROPERTIES (gitignored, chmod 600)"

echo
echo "Fingerprints:"
FINGERPRINTS=$(keytool -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass "$STORE_PASSWORD")
SHA1=$(echo "$FINGERPRINTS"  | grep 'SHA1:'   | head -1 | awk '{print $2}')
SHA256=$(echo "$FINGERPRINTS" | grep 'SHA256:' | head -1 | awk '{print $2}')
echo "  SHA-1:   $SHA1"
echo "  SHA-256: $SHA256"

echo
echo "Registering with Firebase…"
# SHA-1 is what Google Sign-In checks; SHA-256 is what Play Integrity (App
# Check) checks. Both are required — registering only one leaves either
# sign-in or attestation broken in release.
firebase apps:android:sha:create "$APP_ID" "$SHA1"   --project "$PROJECT_ID"
firebase apps:android:sha:create "$APP_ID" "$SHA256" --project "$PROJECT_ID"

echo
echo "✓ Done. Remaining steps:"
echo "  1. flutterfire configure   (refresh google-services.json)"
echo "  2. Back up $KEYSTORE somewhere outside this repo."
echo "  3. If Play re-signs the app, also register the Play App Signing"
echo "     SHA-1 and SHA-256 from the Play Console."
