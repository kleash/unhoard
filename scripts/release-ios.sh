#!/bin/bash
# Archives Unhoard for the App Store (Release, any iOS device), checks the archive, and exports build/ios/Unhoard.ipa
# signed automatically for App Store Connect. With --upload it also uploads the build for TestFlight.
#   DEVELOPMENT_TEAM=<team id> scripts/release-ios.sh [--upload]
# Needs: Xcode signed in to the team (Settings > Accounts) and XcodeGen.
#   BUILD_NUMBER                       optional CFBundleVersion (App Store Connect takes each build number once)
#   APPSTORE_KEY_ID, APPSTORE_ISSUER   optional App Store Connect API key for the upload, its AuthKey_<id>.p8 in
#                                      ~/.appstoreconnect/private_keys; without them Xcode's signed-in account uploads
set -euo pipefail
cd "$(dirname "$0")/.."

upload=false
case "${1:-}" in
    "") ;;
    --upload) upload=true ;;
    *) echo "usage: $0 [--upload]" >&2; exit 2 ;;
esac
fail() { echo "$*" >&2; exit 1; }
[ -n "${DEVELOPMENT_TEAM:-}" ] || fail "DEVELOPMENT_TEAM: the id of the team that signs the app."
version=$(awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2 }' project.yml)
build=${BUILD_NUMBER:-$(awk '/CURRENT_PROJECT_VERSION:/ { gsub(/"/, "", $2); print $2 }' project.yml)}
out=build/ios
archive=$out/Unhoard.xcarchive
ipa=$out/Unhoard.ipa
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

xcodegen generate --quiet
rm -rf "$out"
xcodebuild archive -quiet -project Unhoard.xcodeproj -scheme Unhoard -configuration Release -allowProvisioningUpdates \
    -destination generic/platform=iOS -derivedDataPath build/dd-release -archivePath "$archive" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CURRENT_PROJECT_VERSION="$build"

app=$archive/Products/Applications/Unhoard.app
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Info.plist" 2>/dev/null; }
[ "$(read_plist CFBundleIdentifier)" = com.kleash.unhoard ] || fail "The bundle id isn't com.kleash.unhoard."
[ "$(read_plist CFBundleShortVersionString)" = "$version" ] || fail "CFBundleShortVersionString isn't $version."
[ "$(read_plist CFBundleVersion)" = "$build" ] || fail "CFBundleVersion isn't $build."
[ "$(read_plist CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName)" = AppIcon ] || fail "The app has no icon (AppIcon)."
[ -f "$app/PrivacyInfo.xcprivacy" ] || fail "The app has no PrivacyInfo.xcprivacy."
[ "$(read_plist ITSAppUsesNonExemptEncryption)" = false ] || fail "ITSAppUsesNonExemptEncryption isn't NO."
[ -n "$(read_plist NSPhotoLibraryAddUsageDescription)" ] || fail "Info.plist lacks NSPhotoLibraryAddUsageDescription."
[ -n "$(read_plist NSPhotoLibraryUsageDescription)" ] || fail "Info.plist lacks NSPhotoLibraryUsageDescription (Unhoard reads and deletes)."
[ "$(read_plist UIDeviceFamily:0)" = 1 ] && [ -z "$(read_plist UIDeviceFamily:1)" ] || fail "The app isn't iPhone-only."
[ "$(lipo -archs "$app/Unhoard")" = arm64 ] || fail "The app isn't arm64 alone."

export_options() { # $1: export or upload
    cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$1</string>
	<key>teamID</key>
	<string>$DEVELOPMENT_TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
}
export_options export
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out" -exportOptionsPlist "$work/ExportOptions.plist" \
    -allowProvisioningUpdates
[ -f "$ipa" ] || fail "The export made no $ipa."
unzip -q "$ipa" -d "$work/ipa"
codesign --verify --deep --strict "$work/ipa/Payload/Unhoard.app"
codesign -d --entitlements - --xml "$work/ipa/Payload/Unhoard.app" 2>/dev/null > "$work/signed.plist"
entitlement() { /usr/libexec/PlistBuddy -c "Print :$1" "$work/signed.plist" 2>/dev/null; }
[ "$(entitlement application-identifier)" = "$DEVELOPMENT_TEAM.com.kleash.unhoard" ] \
    || fail "The export is signed for $(entitlement application-identifier), not $DEVELOPMENT_TEAM.com.kleash.unhoard."
[ "$(entitlement get-task-allow)" != true ] || fail "The export is signed for development (get-task-allow)."
echo "Exported $ipa (version $version, build $build)."

if $upload; then
    if [ -n "${APPSTORE_KEY_ID:-}" ] && [ -n "${APPSTORE_ISSUER:-}" ]; then
        xcrun altool --upload-package "$ipa" -t ios --api-key "$APPSTORE_KEY_ID" --api-issuer "$APPSTORE_ISSUER"
    else
        export_options upload
        xcodebuild -exportArchive -archivePath "$archive" -exportPath "$work/upload" \
            -exportOptionsPlist "$work/ExportOptions.plist" -allowProvisioningUpdates
    fi
    echo "Uploaded build $build: it shows in App Store Connect > TestFlight once Apple has processed it."
fi
