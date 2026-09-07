# Mirror recovery status — 2026-09-06

## Usable Android system

The tested MIRROR boots Android 6.0.1 `msm8916_64-userdebug` to Launcher3 at
1920×1080. The original signed bootloader, boot image, kernel, recovery, and
board-specific partitions are preserved. The reconstructed `system` partition
and a fresh Android-compatible `userdata` filesystem are the material changes.

Recovery baseline, with September 6 application/control updates:

| Capability | Result |
| --- | --- |
| Android boot | `sys.boot_completed=1` |
| Display | Android desktop usable; Afterglow now renders in 1080×1920 portrait |
| Userdata | 5.1 GiB total, 4.6 GiB free |
| ADB control | USB previously verified; Wi-Fi `192.168.0.51:5555` authorized and in use |
| Wi-Fi | `SETUP-A040`, `192.168.0.51`, driver status `ok` |
| Phone/Mac remote | Screenshot preview and controls through Mac service on port 8765 |
| Afterglow | `dev.mirror.clock` 0.1; live web clock and bundled fallback tested |
| Dashboard | `dev.mirror.repurpose` 1.8.2; four-digit pairing; local API on port 8787 |
| Bluetooth | Enabled; Android profiles loaded |
| Audio | Speaker playback and built-in microphone recording verified |
| Camera | OV5640 detected; isolated 1080p test receives buffers, but usable imagery/color remains unverified |

## Latest checkpoint

Afterglow was built, installed and visually verified on the Mirror in landscape
and portrait. Portrait is now the remembered setting. The clock keeps a black
background with sparse orbital animation, uses thin Android typography and
displays America/New_York time. It is an ordinary app, not the default launcher.

The Mac's `ux-lab` server serves the live design at port 8766. The app remembers
its live page address and carries bundled assets for offline use. A deliberate
HTTP failure correctly fell back to the bundled clock. Home, relaunch, the
native app menu, Sleep and Wake were tested through the remote.

Installed Afterglow APK SHA-256:

```text
56f4700dfd7c68f1bd9e49d03fdbfee1247f05adc21f6457361da46b966e9dc7
```

The latest prepared sparse system image contains experimental camera
diagnostics and **has not been flashed**:

```text
eedf1f328e0fab49c98425e394a0882141564b9c581e665a05fd0e8c3ce8d249
```

The older hash 2e8f2082… was an earlier recovery checkpoint, not the current
prepared image. No firmware flash was needed for the clock work.

## Durable control

The display has no touch layer. The current path is:

```text
iPhone or Mac browser → local web remote on Mac → authorized Wi-Fi ADB → MIRROR
```

USB serial `be9d0af` remains a fallback. The earlier TCP authorization problem
is no longer present in the current session.

The Mac service starts at login, binds port 8765 on the trusted local network
and keeps the Mac awake while on external power. It opens without an account
or access key. The controls include Back/Home/Recent, D-pad/OK, tap/swipe/text,
volume, Sleep/Wake and app shortcuts, now including Afterglow and App menu.

Screen previews are snapshots, not video. A complex roughly 4 MB screenshot
took about 13 seconds over Wi-Fi, exceeding the old eight-second timeout.
Captures now allow 30 seconds and concurrent requests share a single capture.
Wake sends the keyguard-dismiss menu key only if the lock screen is actually
showing, so waking Afterglow does not accidentally open its menu.

## Wi-Fi, audio, and storage

The preserved stock kernel requires a matching `pronto_wlan` module with this
release string:

```text
3.10.49-perf-gf46dad5260f SMP preempt mod_unload modversions aarch64
```

`mirror-build-running-kernel-wifi.sh` rebuilds it. The module SHA-256 is:

```text
3209948e50a290ede0939586762da074efcd7fbc55f325c84bc0fa680eba40fb
```

The Android Wi-Fi service retries driver loading for up to one minute because
the device node appears several seconds after the framework starts. The
MIRROR now reconnects automatically after cold boot and has working Internet
and DNS.

Audio uses the primary MI2S receive path, both headphone outputs, and the
external-speaker gate. Full-volume speaker playback was audible, and a
three-second recording showed live input from the built-in microphone.

The physical userdata partition is 5,583,458,304 bytes. The successful repair
used the verified Android-6-compatible sparse image at:

```text
captures/adb-userdata-20260904/userdata-adb-raw-chunks.sparse
```

It was sent whole because the device reports a 256 MiB maximum download and
the sparse file is approximately 155 MiB. Do not use the host's current
`fastboot format:ext4 userdata`; its filesystem features produced Android's
`Encryption unsuccessful` screen. Do not add `fastboot -S 128M`; splitting
this custom sparse image caused the later chunk to be rejected.

## Camera boundary

There is one physical front camera. The replacement Android sensor library
labels it BACK, but Android enumerates only one device.

OV5640 discovery and configuration work. Later experiments corrected an
88-byte/104-byte ISP ioctl mismatch, adjusted the CPP initial-AEC failure path,
selected the active CSIPHY0/CSID0 route and built the sensor library with
VFE_40 (combo_mode=0). No usable preview frames arrive; the stream still times
out. Significant PHY interrupt activity does not yet establish correct packet
decoding or the exact remaining cause.

The installed sensor library was read back on September 6 with SHA-256:

```text
e748793df9a7be7576bc94077012fa2ff8afa94564f8bb64925dd6cf6c20048a
```

A diagnostic module to expose CSI registers was built into the prepared image,
but that image remains unflashed and `/proc/mirror_camera_diag` is absent on
the running unit. Camera work is paused. See
[CAMERA-RECOVERY.md](CAMERA-RECOVERY.md) for the corrected route, evidence,
build order and next diagnostic step.

## Flash history and boundaries

Early targeted experiments erased and reformatted only `userdata` and `cache`.
The modern formatter's ext4 feature set was incompatible, and provisioning an
ADB public key alone did not authorize the stock daemon. A reconstructed
Android system was then built and flashed to `system`; the full-size compatible
userdata image restored normal `/data` operation.

No bootloader, boot, recovery, modem, trust, partition-table, or board-specific
firmware partition was replaced. All successful writes were scoped to the
verified fastboot serial `be9d0af`.

## Hardware facts

- Custom board: `MIR63A0-00-P1 / PCA#500240 RevP21`.
- SoC family: Qualcomm APQ8016/MSM8916.
- No microSD slot exists on this board.
- Wi-Fi antenna is connected and handles both 2.4 and 5 GHz.
- `VOL-` during cold power-on enters fastboot; the panel may remain blank.
- `VOL+` enters the signed recovery/update UI.
- UART is exposed at the three-pin `GND TX RX` header and should be treated as
  1.8 V logic.
