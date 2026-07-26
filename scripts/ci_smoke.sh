#!/usr/bin/env bash
# CI smoke test, called by .github/workflows/build-app.yml inside
# reactivecircus/android-emulator-runner. That action runs each script LINE as
# a separate `sh -c`, so state (variables, if-blocks) doesn't survive across
# lines — hence this file: one line in the workflow, full bash in here.
#
# Gates: the APK installs, launches, is still alive 30s later, and logged no
# FATAL EXCEPTION. Writes smoke-home.png as evidence for the artifact upload.
set -euo pipefail

PKG="${1:?usage: ci_smoke.sh <package-id> [apk-path]}"
APK="${2:-app-release.apk}"

echo "Smoke test: $PKG ($APK)"
adb install -r "$APK"
adb logcat -c || true
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
# Give Flutter time to reach the first frame (cold start on swiftshader).
sleep 30
# Evidence first, gates second — so a failure still leaves a screenshot and
# the crash log in the job output for diagnosis.
adb exec-out screencap -p > smoke-home.png || true
# Gate 1: the process must still be alive.
if ! adb shell pidof "$PKG"; then
  echo "::error::App process died within 30s of launch"
  echo "=== crash-relevant logcat ==="
  adb logcat -d | grep -B 2 -A 30 -E "FATAL EXCEPTION|AndroidRuntime|Fatal signal" || true
  echo "=== last 120 logcat lines ==="
  adb logcat -d | tail -120 || true
  exit 1
fi
# Gate 2: no fatal Java/Kotlin crash in the log.
if adb logcat -d | grep -q "FATAL EXCEPTION"; then
  echo "::error::App crashed on launch"
  adb logcat -d | grep -B 2 -A 20 "FATAL EXCEPTION" || true
  exit 1
fi
echo "Smoke test passed."
