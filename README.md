# mirror-mirror

Tools, build notes, and a phone-friendly remote for giving a discontinued
lululemon Studio MIRROR Model One a useful second life.

## Current result

The tested unit now boots a reconstructed Android 6.0.1 desktop in 1080×1920
portrait (native panel: 1920×1080) while retaining its original signed bootloader, boot image, kernel,
recovery, and board-specific partitions. The recovered system has:

- a normal Launcher3 home screen and full 5.1 GiB userdata filesystem;
- automatic Wi-Fi reconnection with working Internet and DNS;
- authorized USB ADB from the owner's Mac;
- a local Mac/iPhone web remote with screenshot previews, tap, swipe, text, Android
  navigation, a directional pad, volume, wake/sleep, and app shortcuts;
- working speakers, microphone, and Bluetooth;
- one front camera with live preview, upright JPEG capture and tested 720p
  software H.264/AAC recording; image brightness and startup reliability still
  need work;
- an optional local dashboard app that is not forced as the Android home app.

The panel is output-only—it has no touch layer. The web remote now works through
authorized Wi-Fi ADB at `192.168.0.51:5555` (verified September 6, 2026), with USB
available as a fallback. Screenshot previews can take several seconds over Wi-Fi.

## Afterglow clock

The **Afterglow** Android app is a clock with subtle orbital geometry
on black. It loads the web experiment from the Mac and includes a bundled clock
for offline use. It defaults to portrait, with portrait/landscape choices in its
app menu. It is an ordinary app; Android still opens on Launcher3.

Start the design server with `node ux-lab/server.mjs`, then use **Afterglow clock**
in the Android remote. Preview the design on the Mac at `http://127.0.0.1:8766/`;
its separate visual remote is at `/remote`. Build/install instructions and the
experimental app architecture are in [clock-app/README.md](clock-app/README.md).

The clock is optional and is not automatically restored after camera tests.
For the complete camera breakdown—sensor compatibility, pixel-format repair,
recording, orientation, diagnostics, tests and remaining limitations—start with
[camera/README.md](camera/README.md). The dated experiments remain in
[CAMERA-RECOVERY.md](CAMERA-RECOVERY.md); the authoritative device snapshot is
[RECOVERY-STATUS.md](RECOVERY-STATUS.md).

## Use the remote

Install the Mac service once:

```sh
./install-mirror-remote.sh
```

Then open:

- Mac: `http://127.0.0.1:8765`
- iPhone on the same Wi-Fi: `http://192.168.0.29:8765`

The installer prints the current iPhone address. The remote opens directly on
a trusted home network with no login prompt. The service starts at Mac login
and keeps the Mac awake while it is connected to power.

The dashboard's own control site is separate: scan the QR shown on the MIRROR
and enter the short four-digit PIN displayed directly beneath it. That pairing
is retained by the phone browser and can be revoked from the dashboard.

Full instructions and troubleshooting are in
[REMOTE-CONTROL.md](REMOTE-CONTROL.md).

For a native Mac window, the remote's **Mac view** button launches `scrcpy`, or
run:

```sh
scrcpy -s be9d0af --window-title "Mirror Control" --stay-awake --no-audio
```

## Rebuild components

The working image is assembled in layers so the preserved stock kernel and
board drivers remain in place:

```sh
./mirror-build-running-kernel-wifi.sh
./mirror-build-ov5640-camera.sh
./mirror-build-camera-compat.sh
./mirror-patch-camera-cpp.sh
./mirror-build-camera-diag.sh
./mirror-build-snapcam.sh
MIRROR_CAMERA_FRONT=1 MIRROR_VIDEO_RAW=1 \
  MIRROR_REBUILD_CAMERA_HAL=1 MIRROR_REBUILD_STAGEFRIGHT=1 \
  ./mirror-build-final-system.sh
```

The final sparse image is ignored by Git at
`artifacts/android-m-msm8916_64/system-mirror-final.img`. The latest local image
was flashed to `system` and boot-verified. Its checkpoint SHA-256 is:

```text
d4f5b63c05ce814a1049a3a3858b9c1a3eb0e12bba7f8178e7ae339014af308a
```

`patches/android-m-mirror-revival.patch` records the owner-key, userdata,
audio, Wi-Fi retry, and product-property source changes. Build artifacts,
captures, credentials, and local source trees are deliberately excluded from
Git.

These scripts require the existing local Android build tree, vendor inputs,
matching kernel build inputs and toolchains; this is not a clean-clone build.
See the [camera build runbook](camera/README.md#build-and-test-runbook) before
rebuilding. Building does not flash the device. Keep `MIRROR_CAMERA_FRONT=1`
explicit: the builder's generic default is `0`.

The optional dashboard is pinned to a known upstream revision and built with:

```sh
./mirror-build-dashboard.sh
```

It is installed as a regular launchable app, not as the system launcher. The
landscape patch also reduces its local-device pairing code to four digits and
keeps the code visible beneath the QR on the 1920×1080 panel.

## Retired-app network tools

The repository also preserves a local replacement for the dead setup flow.
Connect the Mac to the MIRROR's `mirror-*` setup network, then use:

```sh
node mirror-wifi-scan.mjs scan
node mirror-wifi-scan.mjs connect
```

The connect flow prompts locally and never writes or prints the Wi-Fi
password. For the original OS local protocol:

```sh
MIRROR_HOST=192.168.0.51 node mirror-control.mjs status
MIRROR_HOST=192.168.0.51 node mirror-control.mjs features
MIRROR_HOST=192.168.0.51 node mirror-control.mjs dashboard
```

## Hardware notes

- Board: `MIR63A0-00-P1 / PCA#500240 RevP21`, APQ8016/MSM8916 family.
- USB normal boot: Qualcomm Android `05c6:9039`.
- Fastboot: cold power-on while holding PCB `VOL-`; a blank screen is normal.
- Recovery/update UI: cold power-on while holding PCB `VOL+`.
- UART header: `GND`, `TX`, `RX` at the board's three-pin header. Treat it as
  1.8 V logic and never connect the USB-UART adapter's VCC lead.
- This board has no microSD slot.
- The Wi-Fi antenna is a Molex 2.4/5 GHz dual-band antenna, marked `146153`.

The read-only UART helper is safe for initial observation:

```sh
python3 mirror-uart-capture.py --list
python3 mirror-uart-capture.py
```

Connect adapter `GND` to board `GND` and adapter `RXD` to board `TX`; leave
adapter `TXD` and `VCC` disconnected for a read-only capture.

## Important recovery constraints

The modern macOS `fastboot format:ext4 userdata` creates features this Android
6 build cannot mount. The successful userdata recovery used an
Android-compatible sparse ext4 image sent whole, without `fastboot -S`.
Partition writes should always be scoped to the exact verified serial and
partition. See [RECOVERY-STATUS.md](RECOVERY-STATUS.md) before repeating any
flash operation.

## Sources

- [FCC internal photographs](https://fccid.io/2AOSDRLSYM1R0/Internal-Photos/Internal-Photos-3965859)
- [bkerler/edl](https://github.com/bkerler/edl)
- [bkerler/Loaders](https://github.com/bkerler/Loaders)
- [Community dashboard](https://github.com/TimStewartJ/lululemon-mirror-repurpose)
