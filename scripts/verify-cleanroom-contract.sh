#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

required_files='LICENSE_PENDING Package.swift Sources/ClipHaven/ClipHavenApp.swift Sources/ClipHaven/HistoryStore.swift Tests/ClipHavenTests/HistoryStoreTests.swift'
for file in $required_files; do
  test -f "$file" || { echo "missing required file: $file" >&2; exit 1; }
done

test -f assets/ClipHavenIcon.svg
test -f assets/ClipHavenIcon.icns

grep -q 'License selection is intentionally pending' LICENSE_PENDING
grep -q 'retentionDays = 30' Sources/ClipHaven/HistoryStore.swift
grep -q 'ordinaryLimit = 750' Sources/ClipHaven/HistoryStore.swift
grep -q 'diacriticInsensitive' Sources/ClipHaven/HistoryStore.swift
grep -q 'AXIsProcessTrusted' Sources/ClipHaven/ClipHavenApp.swift
grep -q 'RegisterEventHotKey' Sources/ClipHaven/GlobalShortcutController.swift
grep -q 'adjacentDuplicateRefreshesInsteadOfAppending' Tests/ClipHavenTests/HistoryStoreTests.swift

if grep -R -E 'URLSession|NWConnection|CloudKit|MultipeerConnectivity|Analytics' Sources >/dev/null 2>&1; then
  echo 'networking or analytics API found' >&2
  exit 1
fi

if find . -type l -print -quit | grep -q .; then
  echo 'symbolic link found in implementation root' >&2
  exit 1
fi

echo 'clean-room contract: PASS'
