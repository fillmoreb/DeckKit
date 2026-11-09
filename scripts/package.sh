#!/bin/bash
# Builds dist/DeckKit-<version>.zip: every addon folder under addons/, at the top level of the zip,
# ready to unzip into World of Warcraft/_forever_/Interface/AddOns.
#   scripts/package.sh            version from the DeckKit core's .toc
#   scripts/package.sh 1.2.0      or given
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(sed -n 's/^## Version: *//p' addons/DeckKit/DeckKit.toc | tr -d '\r')}"
VERSION="${VERSION#v}"
OUT="dist/DeckKit-$VERSION.zip"
rm -rf dist && mkdir -p dist/stage
for dir in addons/*/; do
    name=$(basename "$dir")
    [ -f "$dir/$name.toc" ] || { echo "skipping $name (no $name.toc)" >&2; continue; }
    cp -R "$dir" "dist/stage/$name"
done
# Readme and license go in with the core, so the zip has no loose files.
cp LICENSE README.md dist/stage/DeckKit/
find dist/stage \( -name '.DS_Store' -o -name '._*' \) -delete
(cd dist/stage && zip -qr -X "../$(basename "$OUT")" .)
rm -rf dist/stage
echo "$OUT"
unzip -l "$OUT" | awk 'NR > 3 && $4 ~ /\/$/ && gsub("/", "/", $4) == 1 { print "  " $4 }'
