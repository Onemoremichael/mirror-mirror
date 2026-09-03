# mirror-mirror

Tools and field notes for recovering local control of the discontinued
lululemon Studio MIRROR Model One without the retired mobile app.

## What works

- Pairing with the MIRROR over its `mirror-*` setup Wi-Fi.
- Scanning for nearby Wi-Fi networks.
- Provisioning a WPA/WPA2 network without storing or printing its password.
- Reading status and using the paired protobuf WebSocket on the local network.

The tested unit runs MIRROR OS 1.27.0 and exposes an HTTP status service on
port 8080 and a protobuf WebSocket at `/socket` on port 7000.

## Requirements

- macOS (the scripts themselves should also work on current Linux)
- Node.js 22 or newer
- A data-capable USB cable for Android/EDL reconnaissance
- Android platform tools for `adb` and `fastboot`

On macOS:

```sh
brew install node android-platform-tools
```

## Restore Wi-Fi setup

Connect the Mac to the MIRROR's `mirror-*` access point, then scan:

```sh
node mirror-wifi-scan.mjs scan
```

To provision a network:

```sh
node mirror-wifi-scan.mjs connect
```

The script prompts locally for the SSID and hides the password. Credentials
are sent directly to the MIRROR and are never written to disk.

## Local-network control

Set the MIRROR's LAN address and read its status:

```sh
MIRROR_HOST=192.168.0.51 node mirror-control.mjs status
```

The `dashboard` command asks the stock UI to return to its dashboard:

```sh
MIRROR_HOST=192.168.0.51 node mirror-control.mjs dashboard
```

The read-only `features` command reports the capabilities advertised by the
installed firmware:

```sh
MIRROR_HOST=192.168.0.51 node mirror-control.mjs features
```

`packages` is retained as a protocol probe, but OS 1.27.0 did not answer that
request on the tested unit.

## Read-only UART capture

Use a USB-UART adapter whose **logic level**, not just its VCC output, is set to
1.8 V. With the MIRROR unplugged, initially connect only:

- Adapter `GND` to MIRROR `GND`.
- Adapter `RXD` to MIRROR `TX` (TP25).

Leave adapter `TXD` and `VCC` disconnected. Plug the adapter into the Mac and
confirm its device path:

```sh
python3 mirror-uart-capture.py --list
```

Start a raw 115200 8N1 capture, then cold-boot the MIRROR:

```sh
python3 mirror-uart-capture.py
```

The script opens the adapter read-only, never transmits, and saves the raw boot
log under the ignored `captures/` directory. Press Control-C after the MIRROR
finishes booting.

## Hardware findings

The reference board in the FCC internal photographs for FCC ID
`2AOSD-RLSYM1R0` shows three tactile switches labeled `PWR`, `VOL+`, and
`VOL-`. They are tiny PCB-mounted switches rather than external controls, and
may be hidden by the installed frame; confirm the board revision before relying
on their presence. The photographed board's reverse side also exposes three
test pads labeled `GND TX RX` (TP25/TP26). Treat the UART as 1.8 V logic until
measured otherwise.

USB behavior observed on the tested APQ8016/MSM8916-family board:

- Normal boot: Qualcomm Android USB `05c6:9039`; ADB is present but reports
  `unauthorized`, and the kiosk UI does not display Android's RSA dialog.
- Early/cold boot: Qualcomm EDL `05c6:9008`.
- Sahara HWID: `0x007060e100000000`.
- Sahara serial: `0x258cecb8`.
- OEM public-key hash:
  `35ac01e7ee8478261aea5134e07e45cb6c5621d42716c15bb10dee0c53d65759`.
- A cold start with USB attached and both PCB volume switches held produced a
  complete Sahara identification exchange. The ROM then requested the ELF
  header, program headers, and hash table from bkerler's public
  `007060e100000000_cc3153a802939b90_fhprg_peek.bin`, but stopped responding
  before executing it. Android subsequently booted normally.
- The device hash does not match that programmer's `cc3153...` signing root.
  This behavior is consistent with secure-boot authentication rejecting the
  loader. Firehose was never entered and no partition I/O occurred. A loader
  signed for the Mirror's `35ac...` root is required before EDL can be used for
  backups or recovery.

Board-button observations on the tested unit:

- A normal cold start requires the external power switch on followed by a
  roughly 3–5 second press of the PCB `PWR` switch.
- Booting while holding PCB `VOL-` leaves the unit in a silent state with no
  ADB, fastboot, or EDL USB enumeration; a full AC power cycle restores it.
- Booting while holding PCB `VOL+` briefly displayed `Update complete!`, then
  returned to normal OS 1.27.0 automatically. No recovery USB transport was
  exposed and the installed OS version did not change.
- Holding both PCB volume switches during a USB-connected cold start can expose
  EDL briefly even though the display later proceeds to the normal boot logo.

## Safety

Current scripts are limited to setup, status, and UI/navigation requests. Do
not send factory-reset, firmware-install, partition erase, or partition write
commands without a verified full backup and a recovery path. In particular,
the updater messages discovered in the retired app do not accept a caller-
supplied URL or APK; the MIRROR chooses vendor update artifacts itself.

## Sources

- [FCC internal photographs](https://fccid.io/2AOSDRLSYM1R0/Internal-Photos/Internal-Photos-3965859)
- [bkerler/edl](https://github.com/bkerler/edl)
- [bkerler/Loaders](https://github.com/bkerler/Loaders)
