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
| Dashboard | `dev.mirror.repurpose` 1.8.2; four-digit pairing; local API on port 8787 |
| Bluetooth | Enabled; Android profiles loaded |
| Audio | Speaker playback and built-in microphone recording verified |
| Camera | Kernel detects OV5640; Android preview not operational |

The final sparse system image has SHA-256:

```text
2e8f2082ac9f416b490630f5f1052d3b48aa297ea3867d79bdc5ce5fe0bb80e4
```

## Durable control

The display has no touch layer. The dependable path is:

```text
iPhone or Mac browser → local web remote on Mac → authorized USB ADB → MIRROR
```

The Mac service starts at login, binds port 8765 on the trusted local network,
and keeps the Mac awake while on external power. It opens without an account or
access-key prompt and offers live screen updates, tap/swipe/text input,
Back/Home/Recent, D-pad/OK, volume, wake/sleep, Settings, dashboard, and native
`scrcpy` launch. Wake also dismisses the credential-free keyguard.

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

The camera now advances substantially beyond the original crash:

1. The stock kernel registers the `ov5640` sensor.
2. Ten Qualcomm media-controller modules omitted by the userdebug product
   recipe are restored, with the narrow fixed-focus compatibility symbols from
   `camera/legacy-camera-compat.c`.
3. The HY22 sensor-library ABI mismatch is corrected. The daemon stays alive,
   Android reports one camera, and applications open it successfully.
4. The library exposes the three modes the kernel actually implements and uses
   the board's explicit two-lane CSI route: lane assignment `0x4320`, mask `7`,
   CSID core/PHY `1`.

The installed OV5640 library has SHA-256:

```text
c268c69d8efa15f603f936c9a5aa987ad4d551bd9eef6472152a8dc4b49d951f
```

Preview is still not claimed as working. The remaining failure is downstream
of sensor discovery and configuration: the legacy Qualcomm ISP reports that it
cannot find a primary format for the OV5640 YUYV stream, stream-on does not
propagate through ISP/CPP/C2D, and applications receive zero frames. There are
no sensor-resolution or CSI-configuration errors in the latest run. This is a
focused vendor ISP-format integration boundary, not a missing camera, broken
sensor, or daemon crash. See [CAMERA-RECOVERY.md](CAMERA-RECOVERY.md) for the
reproducible build and evidence.

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
