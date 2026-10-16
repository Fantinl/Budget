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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Budget" "$APP/Contents/MacOS/Budget"
cp Support/Info.plist "$APP/Contents/Info.plist"
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
