#!/bin/zsh
set -euo pipefail

# Creates one unsaved TextEdit document and verifies the real user flow:
# global shortcut, AppKit row selection, the visible Paste selected control,
# one automatic paste, and an Accessibility-only assertion of TextEdit's
# resulting content.
app_path="${1:-/Users/openclaw/Applications/ClipHaven.app}"
token="CLIPHAVEN_E2E_$(uuidgen | tr '[:lower:]' '[:upper:]')"

[[ -d "$app_path" || -x "$app_path" ]] || { print -u2 "E2E FAIL: app bundle or executable not found: $app_path"; exit 1; }

# Both the installed app and a freshly packaged `dist` app use the same bundle
# identifier.  LaunchServices would otherwise reuse a running older process,
# causing this test to exercise a different bundle than the requested path.
osascript -e 'tell application id "local.cliphaven.app" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
  pgrep -x ClipHaven >/dev/null || break
  sleep 0.1
done
pgrep -x ClipHaven >/dev/null && { print -u2 "E2E FAIL: existing ClipHaven process did not quit"; exit 1; }

if [[ -d "$app_path" ]]; then
  open -gj "$app_path"
else
  "$app_path" >/tmp/cliphaven-e2e-runtime.log 2>&1 &
fi
# Start monitoring before the token is copied, otherwise a fresh process would
# correctly initialize its pasteboard change count *after* this test value.
sleep 1
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' -e 'tell application "TextEdit" to set text of front document to ""'
printf '%s' "$token" | pbcopy
sleep 2
osascript <<APPLESCRIPT
tell application "System Events"
  -- This is the true registered global shortcut, not a menu-bar click.
  key code 49 using {command down, option down}
  delay 0.8
  tell process "ClipHaven"
    if frontmost is false then error "ClipHaven was not frontmost after the global shortcut"
    tell window "ClipHaven History"
      if value of checkbox "Auto-paste (Accessibility required)" is 0 then click checkbox "Auto-paste (Accessibility required)"
      set foundToken to false
      repeat with candidate in rows of table 1 of scroll area 1
        if value of static text 1 of UI element 1 of candidate contains "$token" then
          -- AX selection models an actual table-row selection.
          set selected of candidate to true
          set foundToken to true
          exit repeat
        end if
      end repeat
      if foundToken is false then error "captured E2E row was not visible"
      click button "Paste selected"
    end tell
  end tell
end tell
APPLESCRIPT
sleep 2
frontmost="$(osascript -e 'tell application "System Events" to get name of (first application process whose frontmost is true)')"
actual="$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get value of text area 1 of scroll area 1 of window 1')"
[[ "$frontmost" == "TextEdit" ]] || { print -u2 "E2E FAIL: frontmost app was $frontmost"; exit 1; }
token_count="$(printf '%s' "$actual" | grep -oF "$token" | wc -l | tr -d ' ')"
[[ "$token_count" == "1" ]] || { print -u2 "E2E FAIL: TextEdit did not contain exactly one test token"; exit 1; }
print "E2E PASS: $token"
