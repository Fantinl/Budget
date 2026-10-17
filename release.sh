#!/bin/bash
# Publie une nouvelle version de Budget pour les testeurs.
# Usage : ./release.sh 0.3.0 "Ce qui change dans cette version"
#
# 1. monte le numéro de version (Support/Info.plist), commit et push ;
# 2. compile l'app universelle et crée build/Budget.zip ;
# 3. crée la release GitHub vX.Y.Z avec Budget.zip ;
# 4. signe le zip (clé Sparkle du trousseau) et l'annonce dans appcast.xml, puis push :
#    les apps déjà installées proposent alors la mise à jour.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage : ./release.sh 0.3.0 \"Notes de version\"}"
NOTES="${2:-Corrections et améliorations.}"
REPO="Fantinl/Budget"
PLIST="Support/Info.plist"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
push() { git -c credential.helper= -c credential.helper='!gh auth git-credential' push "$@"; }

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ Il reste des modifications non commitées : commit-les avant de publier."; exit 1
fi
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "❌ La version $VERSION existe déjà."; exit 1
fi

# 1. Numéro de version
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" -c "Set CFBundleVersion $BUILD" "$PLIST"
git commit -qm "Version $VERSION" "$PLIST"
push -q origin main

# 2. Compilation
./build-app.sh --zip

# 3. Release GitHub (le zip doit être en ligne avant d'être annoncé)
gh release create "v$VERSION" build/Budget.zip --repo "$REPO" --target main \
    --title "Budget $VERSION" --notes "$NOTES"

# 4. Signature et annonce dans appcast.xml
SIGNATURE=$("$SPARKLE_BIN/sign_update" build/Budget.zip)   # sparkle:edSignature="…" length="…"
VERSION="$VERSION" BUILD="$BUILD" NOTES="$NOTES" SIGNATURE="$SIGNATURE" REPO="$REPO" python3 - <<'PY'
import html, os
from email.utils import formatdate
v, b, notes, sig, repo = (os.environ[k] for k in ("VERSION", "BUILD", "NOTES", "SIGNATURE", "REPO"))
notes_html = "".join(f"<p>{html.escape(line)}</p>" for line in notes.splitlines() if line.strip())
item = f"""    <item>
      <title>Budget {v}</title>
      <pubDate>{formatdate(localtime=True)}</pubDate>
      <sparkle:version>{b}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes_html}]]></description>
      <enclosure url="https://github.com/{repo}/releases/download/v{v}/Budget.zip" type="application/octet-stream" {sig} />
    </item>
"""
path = "appcast.xml"
s = open(path, encoding="utf-8").read()
marker = "    <language>fr</language>\n"
s = s.replace(marker, marker + item, 1)
open(path, "w", encoding="utf-8").write(s)
PY
git commit -qm "Annonce la version $VERSION" appcast.xml
push -q origin main

echo "✅ Budget $VERSION publiée : https://github.com/$REPO/releases/tag/v$VERSION"
echo "   Les apps installées (0.2.0 ou plus) proposeront la mise à jour."
