#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor/homebrew"
REF="${1:-master}"
BASE_URL="https://raw.githubusercontent.com/Homebrew/brew/${REF}/Library/Homebrew"

mkdir -p "${VENDOR_DIR}/dev-cmd" "${VENDOR_DIR}/version"

curl -fsSL "${BASE_URL}/version.rb" -o "${VENDOR_DIR}/version.rb"
curl -fsSL "${BASE_URL}/version/parser.rb" -o "${VENDOR_DIR}/version/parser.rb"
curl -fsSL "${BASE_URL}/dev-cmd/bump-formula-pr.rb" -o "${VENDOR_DIR}/dev-cmd/bump-formula-pr.rb"

cat > "${VENDOR_DIR}/SOURCE.md" <<EOF
# Homebrew Source Snapshot

- Ref: ${REF}
- Synced at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Files:
- Library/Homebrew/version.rb
- Library/Homebrew/version/parser.rb
- Library/Homebrew/dev-cmd/bump-formula-pr.rb
EOF

echo "Synced Homebrew logic to ${VENDOR_DIR} from ref ${REF}"
