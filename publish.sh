#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Demander la nouvelle version
read -p "Nouvelle version (ex: 1.0.1) : " VERSION

# Mettre à jour la version dans le code source (AutoUpdater.swift)
sed -i '' "s/private let currentVersion = .*/private let currentVersion = \"$VERSION\"/" Sources/OsaNotch/AutoUpdater.swift

# Compiler
echo "▶︎ Compilation..."
./build.sh release

# Zipper
echo "▶︎ Création du .zip..."
rm -f OsaNotch.zip
zip -rq OsaNotch.zip OsaNotch.app

# Créer la release GitHub
echo "▶︎ Publication sur GitHub (v$VERSION)..."
gh release create "v$VERSION" OsaNotch.zip --title "OsaNotch v$VERSION" --notes "Mise à jour automatique."

echo "✅ Publication réussie !"
