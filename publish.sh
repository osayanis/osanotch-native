#!/bin/bash
# Publie une nouvelle version d'OsaNotch :
#  - bump la version dans AutoUpdater.swift
#  - build + zip (ditto)
#  - déploie le canal de MAJ sur le VPS (OsaNotch.zip + latest.json) → notch.osalabs.fr
#  - commit/push + release GitHub
set -euo pipefail
cd "$(dirname "$0")"

VPS="root@141.11.103.154"
SITE="/var/www/osanotch-site"

read -p "Nouvelle version (ex: 1.0.1) : " V
[ -z "$V" ] && { echo "version vide, abandon"; exit 1; }

echo "▶︎ bump version → $V"
sed -i '' "s/private let currentVersion = .*/private let currentVersion = \"$V\"/" Sources/OsaNotch/AutoUpdater.swift

echo "▶︎ build"
./build.sh

echo "▶︎ zip (canal de mise à jour auto)"
rm -f OsaNotch.zip
ditto -c -k --sequesterRsrc --keepParent OsaNotch.app OsaNotch.zip

echo "▶︎ dmg (installation glisser-déposer)"
./make-dmg.sh

echo "▶︎ latest.json"
cat > latest.json <<EOF
{ "version": "$V", "url": "https://notch.osalabs.fr/OsaNotch.zip", "notes": "OsaNotch $V" }
EOF

echo "▶︎ déploiement VPS (canal de mise à jour + téléchargement)"
# le .dmg (installation) et le .zip (MAJ auto) d'abord, le flux ensuite
rsync -az OsaNotch.dmg "$VPS:$SITE/OsaNotch.dmg"
rsync -az OsaNotch.zip "$VPS:$SITE/OsaNotch.zip"
rsync -az latest.json  "$VPS:$SITE/latest.json"

echo "▶︎ git + release GitHub"
git add -A && git commit -m "release: v$V" || true
git push || true
if gh release create "v$V" OsaNotch.dmg OsaNotch.zip --repo osayanis/osanotch-native --title "OsaNotch $V" --notes "OsaNotch $V"; then :; else
  gh release upload "v$V" OsaNotch.dmg OsaNotch.zip --clobber --repo osayanis/osanotch-native
fi

echo "✅ OsaNotch $V publiée — VPS (notch.osalabs.fr) + GitHub."
