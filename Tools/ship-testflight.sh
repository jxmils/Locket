#!/bin/bash
set -euo pipefail
umask 077
archive=${1:?Pass the unsigned Xcode archive}
scratch=$(mktemp -d "$RUNNER_TEMP/stampnote-release.XXXXXX")
keychain="$scratch/signing.keychain-db"
password=$(openssl rand -hex 24)
original=()
while IFS= read -r line; do original+=("$line"); done < <(security list-keychains -d user | sed -E 's/^ *"//;s/"$//')
cleanup() {
  security list-keychains -d user -s "${original[@]}"
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$scratch"
}
trap cleanup EXIT
export API_PRIVATE_KEYS_DIR="$scratch"
export RELEASE_DIR="$scratch"
python3 - <<'PY'
import os, pathlib, base64
p = pathlib.Path(os.environ["RELEASE_DIR"])
for name, f in [("BUILD_CERTIFICATE_BASE64","identity.p12"),("APP_PROVISION_PROFILE_BASE64","Locket.mobileprovision"),("WIDGET_PROVISION_PROFILE_BASE64","Locket.FriendsStamps.mobileprovision")]:
    (p/f).write_bytes(base64.b64decode(os.environ[name],validate=True))
(p/("AuthKey_"+os.environ["APP_STORE_CONNECT_KEY_ID"]+".p8")).write_text(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"])
PY
unset APP_STORE_CONNECT_PRIVATE_KEY BUILD_CERTIFICATE_BASE64 APP_PROVISION_PROFILE_BASE64 WIDGET_PROVISION_PROFILE_BASE64
security create-keychain -p "$password" "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$scratch/identity.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
unset P12_PASSWORD
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "${original[@]}"
fingerprint=$(security find-identity -v -p codesigning "$keychain" | awk '/Apple Distribution/ {print $2; exit}')
test -n "$fingerprint"
app="$scratch/Payload/Locket.app"
mkdir "$scratch/Payload"
ditto "$archive/Products/Applications/Locket.app" "$app"
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")
test "$build" = "$GITHUB_RUN_NUMBER"
for target in "$app/PlugIns/FriendsStamps.appex" "$app"; do
  bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Info.plist")
  case "$bundle" in
    com.jasonmiller.Locket.FriendsStamps) entitlements=Widget/Widget.entitlements ;;
    com.jasonmiller.Locket) entitlements=App/App.entitlements ;;
    *) exit 1 ;;
  esac
  cp "$scratch/${bundle#com.jasonmiller.}.mobileprovision" "$target/embedded.mobileprovision"
  security cms -D -i "$target/embedded.mobileprovision" > "$scratch/profile.plist"
  python3 - "$scratch" "$bundle" "$entitlements" "$fingerprint" <<'PY'
import datetime,hashlib,pathlib,plistlib,sys
directory,bundle,entitlements,fingerprint=sys.argv[1:]
path=pathlib.Path(directory)
profile=plistlib.loads((path/"profile.plist").read_bytes())
assert profile["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
assert any(hashlib.sha1(c).hexdigest().upper()==fingerprint for c in profile["DeveloperCertificates"])
grants=profile["Entitlements"]
assert grants["application-identifier"]=="KY3DU2D7QL."+bundle and not grants["get-task-allow"] and grants["beta-reports-active"]
signed=plistlib.loads(pathlib.Path(entitlements).read_bytes())
for field,values in signed.items():
    assert all(v in grants[field] or "*" in grants[field] for v in values),field
for field in ["application-identifier","com.apple.developer.team-identifier","get-task-allow","beta-reports-active"]:
    signed[field]=grants[field]
signed["com.apple.developer.icloud-container-environment"]="Production"
(path/"target.plist").write_bytes(plistlib.dumps(signed))
PY
  codesign --force --sign "$fingerprint" --keychain "$keychain" --entitlements "$scratch/target.plist" --generate-entitlement-der --timestamp=none "$target"
done
codesign --verify --deep --strict "$app"
ditto -c -k --norsrc --keepParent "$scratch/Payload" "$scratch/Stampnote.ipa"
if [[ "$(node Tools/testflight.mjs lookup "$build")" == missing ]]; then
  xcrun altool --upload-app --type ios --file "$scratch/Stampnote.ipa" --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
fi
node Tools/testflight.mjs wait "$build"
