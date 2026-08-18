#!/bin/bash
# One-command Mac setup: generates Word.xcodeproj from project.yml and opens it.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen (via Homebrew)…"
  brew install xcodegen
fi

xcodegen generate

cat <<'NOTE'

Project generated. One manual step the first time only:
  Xcode → Word target → Signing & Capabilities → pick your Team.

Then select the Word scheme (iPhone simulator, or My Mac) and press Run —
you should see WordCore dealing the same 20 letters the web game deals for
seed "hello".
NOTE

open Word.xcodeproj
