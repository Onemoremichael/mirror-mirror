#!/bin/zsh

# Read-only reconnaissance for the Mirror's temporary setup Wi-Fi network.
# Run this after manually joining mirror-be9d0af from macOS Wi-Fi settings.

set -u

output_file="/Users/mj/Documents/mirror-mirror/mirror-network-scan.txt"
work_dir="$(mktemp -d /tmp/mirror-network-scan.XXXXXX)"

exec > >(tee "$output_file") 2>&1

echo "Mirror network scan"
date
echo

local_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
gateway="$(route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"

echo "Interface: en0"
echo "Local IP: ${local_ip:-unavailable}"
echo "Gateway: ${gateway:-unavailable}"
echo

echo "DHCP details"
ipconfig getpacket en0 2>/dev/null || true
echo

if [[ ! "$local_ip" =~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "No IPv4 address was assigned. Confirm that the Mac is joined to mirror-be9d0af, then rerun this script."
  exit 1
fi

subnet="${local_ip%.*}.0/24"
echo "Discovering devices on $subnet"
/opt/homebrew/bin/nmap -sn "$subnet" -oG "$work_dir/live.gnmap"
echo

echo "ARP table"
arp -an
echo

targets=("${(@f)$(awk '/Up$/{print $2}' "$work_dir/live.gnmap")}")
if (( ${#targets[@]} == 0 )); then
  targets=("$gateway")
fi

echo "Live targets: ${targets[*]}"
echo

echo "Common services"
/opt/homebrew/bin/nmap -Pn -sT -sV --version-light --max-retries 1 --host-timeout 90s \
  -p 21,22,23,53,80,443,5555,7000,8000,8008,8080,8081,8443,8888,9000,10000 \
  "${targets[@]}" || true
echo

if [[ -n "$gateway" && "$gateway" =~ '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "All TCP ports on gateway $gateway"
  /opt/homebrew/bin/nmap -Pn -sT -p- --min-rate 500 --max-retries 1 --host-timeout 120s "$gateway" || true
  echo
fi

echo "HTTP probes"
for host in "${targets[@]}"; do
  for port in 80 443 5555 7000 8000 8008 8080 8081 8443 8888 9000 10000; do
    for scheme in http https; do
      url="$scheme://$host:$port/"
      response="$(curl -k -i -L --max-time 3 --max-filesize 131072 "$url" 2>/dev/null || true)"
      if [[ -n "$response" ]]; then
        echo "----- $url -----"
        print -r -- "$response" | sed -n '1,160p'
        echo
      fi
    done
  done
done

echo "Finished. Results saved to: $output_file"
