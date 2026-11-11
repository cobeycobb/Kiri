#!/bin/zsh
set -eu
cd "${0:A:h:h}"

./scripts/build.sh
ARCH="$(uname -m)"
PACKAGE="$PWD/dist/Kiri-Share-$ARCH"
mkdir -p "$PACKAGE"
ditto "$PWD/dist/Kiri.app" "$PACKAGE/Kiri.app"
cp SETUP.txt "$PACKAGE/START HERE.txt"
codesign --verify --deep --strict "$PACKAGE/Kiri.app"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE" "$PACKAGE.zip"
printf '\nShare this file: %s.zip\n' "$PACKAGE"
