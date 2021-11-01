#!/usr/bin/env bash
#
# Requires environment variables:
#   GITHUB_TOKEN    A token with access to the fossas/basis repository
#
# Requires binary dependencies in $PATH:
#   jq              Parse and manipulate json structures.
#   curl            Download data over HTTP(s)
#   sed             Modify syft tag
#   upx             Compress binaries (optional)
#

set -e

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Provide your GITHUB_TOKEN in the environment"
  exit 1
fi

rm -f vendor-bins/*
mkdir -p vendor-bins

ASSET_POSTFIX=""
WIGGINS_ASSET_POSTFIX=""
OS_WINDOWS=false
case "$(uname -s)" in
  Darwin)
    ASSET_POSTFIX="darwin"
    WIGGINS_ASSET_POSTFIX="darwin-amd64"
    ;;

  Linux)
    ASSET_POSTFIX="linux"
    WIGGINS_ASSET_POSTFIX="linux-amd64"
    ;;

  *)
    echo "Warn: Assuming $(uname -s) is Windows"
    ASSET_POSTFIX="windows.exe"
    WIGGINS_ASSET_POSTFIX="windows-amd64"
    OS_WINDOWS=true
    ;;
esac

TAG="latest"
echo "Downloading asset information from latest tag for architecture '$ASSET_POSTFIX'"

WIGGINS_TAG="2021-10-28-4a27736"
echo "Downloading wiggins binary"
echo "Using wiggins release: $WIGGINS_TAG"
WIGGINS_RELEASE_JSON=vendor-bins/wiggins-release.json
curl -sSL \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3.raw" \
    api.github.com/repos/fossas/basis/releases/tags/$WIGGINS_TAG > $WIGGINS_RELEASE_JSON

WIGGINS_TAG=$(jq -cr ".name" $WIGGINS_RELEASE_JSON)
FILTER=".name == \"scotland_yard-wiggins-$WIGGINS_ASSET_POSTFIX\""
jq -c ".assets | map({url: .url, name: .name}) | map(select($FILTER)) | .[]" $WIGGINS_RELEASE_JSON | while read ASSET; do
  URL="$(echo $ASSET | jq -c -r '.url')"
  NAME="$(echo $ASSET | jq -c -r '.name')"
  OUTPUT="$(echo vendor-bins/$NAME | sed 's/scotland_yard-//' | sed 's/-'$WIGGINS_ASSET_POSTFIX'$//')"

  echo "Downloading '$NAME' to '$OUTPUT'"
  curl -sL -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/octet-stream" -s $URL > $OUTPUT
done
rm $WIGGINS_RELEASE_JSON
echo "Wiggins download successful"
echo

if $OS_WINDOWS; then
  echo "Skipping syft for Windows builds"
  touch vendor-bins/syft
else
  echo "Downloading forked syft binary"
  SYFT_RELEASE_JSON=vendor-bins/syft-release.json
  curl -sSL \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github.v3.raw" \
      api.github.com/repos/fossas/syft/releases/latest > $SYFT_RELEASE_JSON

  # Remove leading 'v' from version tag
  # 'v123' -> '123'
  SYFT_TAG=$(jq -cr '.name' $SYFT_RELEASE_JSON | sed 's/^v//')
  echo "Using fossas/syft release: $SYFT_TAG"
  FILTER=".name == \"container-scanning_${SYFT_TAG}_${ASSET_POSTFIX}_amd64.tar.gz\""
  jq -c ".assets | map({url: .url, name: .name}) | map(select($FILTER)) | .[]" $SYFT_RELEASE_JSON | while read ASSET; do
    URL="$(echo $ASSET | jq -c -r '.url')"
    NAME="$(echo $ASSET | jq -c -r '.name')"
    OUTPUT=vendor-bins/${NAME%"-$ASSET_POSTFIX"}

    echo "Downloading '$NAME' to '$OUTPUT'"
    curl -sL -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/octet-stream" -s $URL > $OUTPUT
    echo "Extracting syft binary from tarball"
    tar xzf $OUTPUT fossa-container-scanning
    mv fossa-container-scanning vendor-bins/syft
    rm $OUTPUT

  done
  rm $SYFT_RELEASE_JSON
  echo "Forked Syft download successful"
fi

echo "Marking binaries executable"
chmod +x vendor-bins/*

echo "Compressing binaries"
upx vendor-bins/* || echo "WARN: 'upx' command not found, binaries will not be compressed"

echo "Vendored binaries are ready for use"
ls -lh vendor-bins/
