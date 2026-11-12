#!/bin/zsh
# Archives TrackStar and uploads it to App Store Connect for TestFlight, in one command:
#
#   scripts/testflight.sh                         # next build number, archive, upload
#   scripts/testflight.sh --notes-file notes.txt  # ...then, once processed, set What to Test and send it to every
#                                                 #    tester group (see scripts/asc.swift)
#   scripts/testflight.sh --check                 # archive and export only (no upload, build number unchanged)
#
# Needs an App Store Connect API key (App Store Connect › Users and Access › Integrations › Team Keys) with Admin
# access: Apple only lets Admin keys sign with its cloud-managed distribution certificate. Put its details in Config/AppStoreConnect.env, which git ignores:
#
#   ASC_KEY_ID=ABC123DEFG
#   ASC_ISSUER_ID=12345678-aaaa-bbbb-cccc-1234567890ab
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_ABC123DEFG.p8   # optional; this is the default
#
# The key signs and uploads without Xcode's Accounts settings, and creates the distribution certificate and
# profiles the first time if they're missing.
set -euo pipefail

cd "$(dirname "$0")/.."
check_only=false
notes_file=""
while (( $# )); do
    case $1 in
        --check) check_only=true ;;
        --notes-file) notes_file=${2:?--notes-file needs a file}; shift ;;
        *) echo "Unknown option $1" >&2; exit 1 ;;
    esac
    shift
done
if [[ -n $notes_file && ! -f $notes_file ]]; then
    echo "Can't find $notes_file." >&2
    exit 1
fi

config=Config/AppStoreConnect.env
if [[ ! -f $config ]]; then
    echo "Missing $config: see the top of this script for what goes in it." >&2
    exit 1
fi
source $config
: "${ASC_KEY_ID:?ASC_KEY_ID isn't set in $config}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID isn't set in $config}"
key_path=${ASC_KEY_PATH:-~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}
key_path=${key_path/#\~/$HOME}
if [[ ! -f $key_path ]]; then
    echo "Can't find the API key file at $key_path." >&2
    exit 1
fi
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key_path"
      -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

team=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig 2>/dev/null | head -1)
if [[ -z $team ]]; then
    echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig first." >&2
    exit 1
fi
if grep -qE '^STRAVA_CLIENT_SECRET(_NO_SERVER)? *= *[A-Za-z0-9]{10,}' Config/Local.xcconfig; then
    echo "Note: Config/Local.xcconfig has a Strava client secret. The server adds it now, so delete that line." >&2
fi
if [[ -n $(git status --porcelain) ]]; then
    echo "Note: there are uncommitted changes; they'll be in this build."
fi

# App Store Connect needs a new build number for every upload.
build=$(sed -n 's/^CURRENT_PROJECT_VERSION = \([0-9]*\)$/\1/p' Config/App.xcconfig)
version=$(sed -n 's/^MARKETING_VERSION = \(.*\)$/\1/p' Config/App.xcconfig)
if ! $check_only; then
    build=$((build + 1))
    sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $build/" Config/App.xcconfig
fi
echo "TrackStar $version ($build)"

archive=.build/archives/TrackStar-$version-$build.xcarchive
rm -rf "$archive"
echo "Archiving…"
xcodebuild archive -project TrackStar.xcodeproj -scheme TrackStar -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" "${auth[@]}" -quiet

export_options=$(mktemp -t trackstar-export).plist
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$($check_only && echo export || echo upload)</string>
    <key>teamID</key><string>$team</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo $($check_only && echo "Exporting (no upload)…" || echo "Uploading to App Store Connect…")
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" \
    -exportPath .build/export "${auth[@]}" -quiet
rm -f "$export_options"

if $check_only; then
    echo "Done: .build/export/TrackStar.ipa is signed for the App Store. Nothing was uploaded."
else
    echo "Uploaded $version ($build). It shows in TestFlight after processing, usually 10 to 30 minutes."
    if [[ -n $notes_file ]]; then
        swift scripts/asc.swift distribute --build "$build" --notes-file "$notes_file"
    fi
    echo "Commit the new build number: git commit -am \"TestFlight build $build\""
fi
