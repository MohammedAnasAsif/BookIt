#!/usr/bin/env bash
# Installs the APK, opens demo screens and records screenshots + crashes.
set -u
apk="$1"
pkg=io.github.mohammedanasasif.bookit
out=android-shots
mkdir -p "$out"
adb install -r "$apk" || { echo "install failed" | tee "$out/result.txt"; exit 1; }
adb shell getprop ro.build.version.release > "$out/android-version.txt"
fail=0
for args in "--demo=home" "--demo=store" "--demo=bookPage" "--demo=readNow" "--demo=reader" "--demo=readerMenu" \
            "--demo=library" "--demo=settings" "--demo=statsCard" "--demo=quote" "--demo=home --ui=ta" "--demo=readerMenu --ui=hi"; do
  name=$(echo "$args" | sed 's/--demo=//; s/ --ui=/-/')
  adb logcat -c
  adb shell am force-stop $pkg
  adb shell am start -W -n $pkg/.MainActivity --es bookit_args "'$args'" > /dev/null
  wait=12; case "$name" in home|home-*|store|bookPage|readNow) wait=30;; esac
  sleep $wait
  adb exec-out screencap -p > "$out/$name.png"
  if ! adb shell pidof $pkg > /dev/null; then
    echo "$name: app is not running (crashed?)" | tee -a "$out/result.txt"; fail=1
  fi
  adb logcat -d > "$out/logcat-$name.txt"
  if grep -qE "FATAL EXCEPTION|E/flutter.*Unhandled Exception" "$out/logcat-$name.txt"; then
    echo "$name: error in log" | tee -a "$out/result.txt"
    grep -E -A12 "FATAL EXCEPTION|E/flutter" "$out/logcat-$name.txt" | head -60 >> "$out/result.txt"
    fail=1
  else
    rm "$out/logcat-$name.txt"
  fi
done
echo "fail=$fail" | tee -a "$out/result.txt"
exit $fail
