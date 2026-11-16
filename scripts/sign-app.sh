#!/bin/bash
# Signs a built app bundle. Usage: sign-app.sh <app path> <bundle identifier>
# Uses the local signing identity named by GLASSDOCK_SIGN_IDENTITY (default "NotchUnlock Local Signing") when the login
# keychain lists it, so the code identity stays the same across rebuilds and macOS keeps the Accessibility and Screen
# Recording permissions. Otherwise signs ad hoc, which resets those permissions on every rebuild.
set -euo pipefail

APP="$1"
BUNDLE_ID="$2"
IDENTITY="${GLASSDOCK_SIGN_IDENTITY:-NotchUnlock Local Signing}"

sign_ad_hoc() {
    codesign --force --sign - "$APP" >/dev/null
    echo "WARNING: signed $APP ad hoc, so macOS will reset its Accessibility and Screen Recording permissions on every rebuild." >&2
}

if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "WARNING: signing identity \"$IDENTITY\" not found in the keychain." >&2
    sign_ad_hoc
    exit 0
fi

if error=$(codesign --force --sign "$IDENTITY" "$APP"/Contents/MacOS/*.dylib 2>&1 \
    && codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>&1); then
    echo "Signed $APP with \"$IDENTITY\" ($BUNDLE_ID)"
else
    echo "WARNING: codesign could not use \"$IDENTITY\": $error" >&2
    sign_ad_hoc
fi
