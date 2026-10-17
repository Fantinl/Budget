#!/bin/bash
# Compile l'app en release et crée build/Budget.app.
# Usage : ./build-app.sh            -> crée build/Budget.app
#         ./build-app.sh --install  -> copie aussi l'app dans /Applications
#         ./build-app.sh --zip      -> crée aussi build/Budget.zip (à publier dans une release GitHub)
set -euo pipefail
cd "$(dirname "$0")"

# Utilise Xcode s'il est installé (nécessaire pour les macros SwiftUI comme @State).
if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Binaire universel : Mac Apple Silicon et Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/Budget.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Budget" "$APP/Contents/MacOS/Budget"
cp Support/Info.plist "$APP/Contents/Info.plist"
[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle (mises à jour) : framework embarqué, liens symboliques préservés.
SPARKLE="$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -maxdepth 6 | head -1)"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# Signature ad hoc (pas de compte Apple Developer) : composants de Sparkle d'abord, puis l'app.
for item in "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/*.xpc \
            "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate \
            "$APP"/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app \
            "$APP"/Contents/Frameworks/Sparkle.framework; do
    [[ -e "$item" ]] && codesign --force --sign - "$item"
done
codesign --force --sign - "$APP"

echo "✅ $APP créé"

if [[ "${1:-}" == "--zip" ]]; then
    rm -f build/Budget.zip
    ditto -c -k --keepParent "$APP" build/Budget.zip
    echo "✅ build/Budget.zip créé"
fi

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Budget.app
    cp -R "$APP" /Applications/
    echo "✅ Installé dans /Applications"
fi
