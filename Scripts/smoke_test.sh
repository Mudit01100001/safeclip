#!/bin/bash
# SafeClip security smoke test (CLAUDE.md / PRD §16).
# Launches a fresh debug build, captures real copies, and asserts the on-disk
# security guarantees. DESTRUCTIVE: wipes local SafeClip history first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/SafeClip.app"
DB="$HOME/Library/Application Support/SafeClip/history.db"
FAIL=0

echo "── building…"
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Debug \
  -derivedDataPath build build -quiet

echo "── fresh launch (onboarding pre-seeded)…"
pkill -x SafeClip 2>/dev/null || true; sleep 1
rm -rf "$HOME/Library/Application Support/SafeClip"
defaults write com.mudit.safeclip hasCompletedOnboarding -bool true
open "$APP"; sleep 6   # cold start must finish before the first copy — the monitor skips pre-launch clipboard content by design
pgrep -x SafeClip >/dev/null || { echo "FAIL: app not running"; exit 1; }

echo "── capturing test copies (text, password, image, file)…"
printf 'smoke-public-note-12345' | pbcopy; sleep 1.5
printf 'MyS3cretPassw0rd-smoke!' | pbcopy; sleep 1.5
PNG=/tmp/safeclip_smoke.png
echo 'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR42mP8z8BQz0AEYBxVSF+FAAhKBAGcU3qbAAAAAElFTkSuQmCC' | base64 -d > "$PNG"
osascript -e "set the clipboard to (read (POSIX file \"$PNG\") as «class PNGf»)"; sleep 1.5
osascript -e "set the clipboard to POSIX file \"$PNG\""; sleep 1.5

ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM clips;")
[ "$ROWS" -eq 4 ] && echo "OK: 4 rows captured" || { echo "FAIL: expected 4 rows, got $ROWS (did macOS clipboard permission block reads?)"; FAIL=1; }
KINDS=$(sqlite3 "$DB" "SELECT GROUP_CONCAT(DISTINCT kind) FROM clips;")
echo "kinds present: $KINDS"
sqlite3 "$DB" "SELECT COUNT(*) FROM clips WHERE kind='image' AND thumb_cipher IS NOT NULL;" | grep -q 1 \
  && echo "OK: image row with encrypted thumbnail" || { echo "FAIL: no image row"; FAIL=1; }
xxd -p "$DB" | tr -d '\n' | grep -qo "89504e47" \
  && { echo "FAIL: raw PNG magic on disk — image payload not encrypted"; FAIL=1; } \
  || echo "OK: image payload encrypted (no PNG magic bytes)"
rm -f "$PNG"

echo "── F1: no plaintext on disk…"
for needle in "smoke-public" "MyS3cretPassw0rd"; do
  if strings "$DB" | grep -q "$needle" || xxd "$DB" | grep -q "$needle"; then
    echo "FAIL: '$needle' leaked to disk"; FAIL=1
  else
    echo "OK: '$needle' not on disk"
  fi
done

echo "── keychain key present…"
security find-generic-password -s SafeClip >/dev/null 2>&1 \
  && echo "OK: master key in Keychain" || { echo "FAIL: no keychain item"; FAIL=1; }

echo "── dedup…"
printf 'smoke-public-note-12345' | pbcopy; sleep 1.5
ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM clips;")
[ "$ROWS" -eq 4 ] && echo "OK: re-copy deduplicated" || { echo "FAIL: dedup broken ($ROWS rows)"; FAIL=1; }

echo "── persistence across relaunch…"
pkill -x SafeClip; sleep 2; open "$APP"; sleep 6
ROWS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM clips;")
[ "$ROWS" -eq 4 ] && echo "OK: history persisted" || { echo "FAIL: history lost ($ROWS rows)"; FAIL=1; }

pkill -x SafeClip 2>/dev/null || true
[ "$FAIL" -eq 0 ] && echo "✅ smoke test passed" || { echo "❌ smoke test FAILED"; exit 1; }
