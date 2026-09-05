# Mirror recovery status — 2026-09-05

## Usable Android system

The tested MIRROR boots Android 6.0.1 `msm8916_64-userdebug` to Launcher3 at
1920×1080. The original signed bootloader, boot image, kernel, recovery, and
board-specific partitions are preserved. The reconstructed `system` partition
and a fresh Android-compatible `userdata` filesystem are the material changes.

Verified after the final reboot:

| Capability | Result |
| --- | --- |
| Android boot | `sys.boot_completed=1` |
| Display | 1920×1080 landscape; Launcher3 visible; keyguard dismissed |
| Userdata | 5.1 GiB total, 4.6 GiB free |
| USB control | ADB authorized as serial `be9d0af` |
| Wi-Fi | `SETUP-A040`, `192.168.0.51`, driver status `ok` |
| Phone/Mac remote | Live screen and controls through Mac service on port 8765 |
| Dashboard | `dev.mirror.repurpose` 1.8.2; local API on port 8787 |
| Bluetooth | Enabled; Android profiles loaded |
| Audio | Speaker playback and built-in microphone recording verified |
| Camera | Kernel detects OV5640; Android preview not operational |

The final sparse system image has SHA-256:

```text
ea407a2d5a6ca8f15438c4f0d4f0a1d39a406935ed5f21cc9d8e4f20129e69c6
```

## Durable control

The display has no touch layer. The dependable path is:

```text
iPhone or Mac browser → private web remote on Mac → authorized USB ADB → MIRROR
```

The Mac service starts at login, binds port 8765, requires a generated private
access key, and keeps the Mac awake while on external power. It offers live
screen updates, tap/swipe/text input, Back/Home/Recent, D-pad/OK, volume,
wake/sleep, Settings, dashboard, and native `scrcpy` launch. Wake also dismisses
the credential-free keyguard.

Direct TCP ADB reaches `192.168.0.51:5555`, and the framework recognizes the
owner's key, but this old daemon leaves the TCP transport unauthorized while
USB remains the verified transport. The web bridge therefore prefers an
authorized connection and safely falls back to the USB serial.

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

Camera work progressed through three distinct failures:

1. The stock kernel registers `ov5640` successfully.
2. A pinned OV5640 sensor library was built and installed with SHA-256
   `71e6dbe713bc3314c76da69d2107558bcba2f25dd17401c780cafe2748278a68`.
3. Ten Qualcomm media-controller modules omitted by the userdebug product
   recipe were restored. Missing fixed-focus hybrid-AF symbols were supplied by
   the narrow compatibility library in `camera/legacy-camera-compat.c`.

The camera daemon now links and begins sensor initialization, but exits with
SIGSEGV in the vendor sensor module:

```text
libmmcamera2_sensor_modules.so: port_sensor_create+443
liboemcamera.so: mct_list_traverse+26
libmmcamera2_sensor_modules.so: module_sensor_init+264
```

Disassembly identifies the faulting load as access to
`sensor_stream_info_array->sensor_stream_info[j].vc_cfg_size`. The pointer
returned by the OV5640 sensor library does not match the prebuilt sensor
module's expected layout. That is strong evidence of an ABI mismatch between
the available legacy Qualcomm source and binary set. Camera preview is not
claimed as working; the next defensible attempt is to build the sensor media
controller from the same source family as the OV5640 library, not to replace
more partitions.

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
