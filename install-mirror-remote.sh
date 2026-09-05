#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
launch_agents="$HOME/Library/LaunchAgents"
agent="$launch_agents/com.mirror.remote-control.plist"
app_support="$HOME/Library/Application Support/Mirror Remote"
uid=$(id -u)

mkdir -p "$launch_agents" "$HOME/Library/Logs" "$app_support"
cp "$repo_root/remote-control/server.mjs" "$app_support/server.mjs"
cp "$repo_root/remote-control/index.html" "$app_support/index.html"
cp "$repo_root/remote-control/app.js" "$app_support/app.js"
cp "$repo_root/remote-control/styles.css" "$app_support/styles.css"
cp "$repo_root/remote-control/com.mirror.remote-control.plist" "$agent"
rm -f "$app_support/.remote-control-token"
launchctl bootout "gui/$uid/com.mirror.remote-control" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$agent"
launchctl enable "gui/$uid/com.mirror.remote-control"

remote_ready=0
for _ in {1..20}; do
  if curl --silent --fail --max-time 1 http://127.0.0.1:8765/ >/dev/null; then
    remote_ready=1
    break
  fi
  sleep 1
done
if [[ "$remote_ready" != 1 ]]; then
  echo "Mirror Remote did not become ready; check ~/Library/Logs/mirror-remote-error.log" >&2
  exit 1
fi

network_interface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
lan_address=""
if [[ -n "$network_interface" ]]; then
  lan_address=$(ipconfig getifaddr "$network_interface" 2>/dev/null || true)
fi

echo "Mirror Remote installed and running."
echo "Open http://127.0.0.1:8765 on this Mac."
if [[ -n "$lan_address" ]]; then
  echo "On an iPhone using the same Wi-Fi, open http://$lan_address:8765."
else
  echo "For an iPhone on the same Wi-Fi, use this Mac's LAN address on port 8765."
fi
