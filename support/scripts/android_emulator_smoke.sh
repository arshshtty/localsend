#!/usr/bin/env bash
# Smoke test for QA F3: install debug APK on a booted emulator, launch it,
# confirm it stays up, and confirm the MulticastLock path ran without crashing.
set -uo pipefail
APK="${1:?usage: android_emulator_smoke.sh <apk> [outdir]}"
OUT="${2:-smoke-logs}"
PKG="org.localsend.localsend_app.debug"
ACT="org.localsend.localsend_app.MainActivity"
SETTLE="${SETTLE_SECONDS:-30}"
mkdir -p "$OUT"
fail() { echo "SMOKE FAIL: $*"; adb logcat -d > "$OUT/logcat.txt" 2>&1; exit 1; }

adb wait-for-device
adb install -r -g "$APK" || fail "install failed"
adb logcat -c
adb shell am start -W -n "$PKG/$ACT" | tee "$OUT/am-start.txt"
grep -q "Status: ok" "$OUT/am-start.txt" || fail "launch failed"

for i in $(seq 1 "$SETTLE"); do
  sleep 1
  adb shell pidof "$PKG" >/dev/null || fail "process died after ${i}s"
done
adb shell dumpsys wifi > "$OUT/dumpsys-wifi.txt" 2>&1
adb shell dumpsys activity activities | grep -i "$PKG" > "$OUT/activity.txt" || true
adb logcat -d > "$OUT/logcat.txt"

if grep -E "FATAL EXCEPTION|AndroidRuntime.*$PKG|Process: $PKG" "$OUT/logcat.txt"; then
  fail "crash in logcat"
fi
if grep -q "Could not update multicast lock" "$OUT/logcat.txt"; then
  fail "MulticastLockHolder reported an error"
fi
# MulticastLockHolder creates a lock tagged "localsend" and holds it while foregrounded.
if grep -iA20 "multicast" "$OUT/dumpsys-wifi.txt" | grep -q "localsend"; then
  echo "MulticastLock 'localsend' held while foregrounded"
else
  echo "WARNING: 'localsend' MulticastLock not visible in dumpsys wifi (emulator Wi-Fi may be off)"
  [ "${REQUIRE_MULTICAST_LOCK:-0}" = "1" ] && fail "multicast lock not held"
fi
echo "SMOKE PASS"
