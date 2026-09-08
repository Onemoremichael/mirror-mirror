# Mirror recovery status

Current checkpoint: September 8, 2026 device logs. Historical candidates belong
in [CAMERA-RECOVERY.md](CAMERA-RECOVERY.md), not this current-state snapshot.

## Installed system

The current image enables the narrowly scoped exposure bridge and experimental
gain headroom. The stock exposure command was a successful no-op; live sensor
target changes now work. Positive compensation raises gain and measured preview
brightness about 1.9×, but severe darkness/noise remains. Historical diagnostic
and target-only images are recorded in the lab log, not installed concurrently.

The tested board boots Android 6.0.1 `msm8916_64-userdebug` to Launcher3.
Its signed bootloader, boot image, Linux kernel, recovery and board-specific
partitions remain preserved. Reconstructed `system` and an Android-compatible
`userdata` filesystem provide the usable installation.

| Capability | Last verified result |
| --- | --- |
| Android boot | `sys.boot_completed=1` |
| Display | Portrait 1080×1920 desktop; native panel 1920×1080; no touch layer |
| Storage | Full 5.1 GiB userdata filesystem; 4.6 GiB free at the earlier storage check |
| Control | Authorized USB ADB (`be9d0af`) and Wi-Fi ADB (`192.168.0.51:5555`) |
| Wi-Fi | Automatic reconnection, working Internet and DNS |
| Remote | Mac/iPhone browser controls and screenshot previews through Mac port 8765 |
| Audio | Audible speaker playback and built-in microphone recording |
| Bluetooth | Enabled and Android profiles loaded; not a claim that every peripheral was tested |
| Camera | One FRONT/0 camera; upright live preview, JPEG and 720p software H.264/AAC video |
| Camera limitations | Severe darkness, historical intermittent startup, hardware encoder and perceptual A/V sync unresolved |
| Afterglow | Landscape/portrait and bundled offline fallback tested; ordinary optional app |
| Dashboard | Regular app with four-digit pairing, not the Android launcher |

The clock is not automatically restored after tests. User preference is to open
Android normally and choose apps through the remote. There are no physical
front/back camera pairs: old BACK metadata was a software label.

## Current image and camera checkpoint

Installed sparse `system-mirror-final.img` SHA-256:

```text
a6b0c96810b9b0ef2998a2ec2e83614fb77b4aa1170c3c0f13a1358e39d67a38
```

It was flashed to `system` in 77.996 seconds and boot-verified. Its camera
configuration is FRONT/0, default settle count 0x18, normal C2D (sampling wrapper
disabled), quiet processing logs, and `debug.mirror.video_raw=1` loaded from
`build.prop` after reboot. `debug.mirror.exposure_bridge=1` and
`debug.mirror.gain_headroom=1` are enabled; builders default both to 0, so retain
them explicitly to reproduce this experimental configuration. No manual
recording-property setup is now required.

Current Snapcam APK SHA-256:

```text
ba9c9c7a8da7122479ca30ca177ad0f49307796a78a8ed4dab4ba497429142da
```

Photo and video preview proportions and saved orientation were corrected for
the sensor-less portrait installation. Latest ordinary-app video: 413 frames
over 18.1235 seconds (~22.79 fps), H.264 at the Mirror-specific 4 Mbps 720p
setting, with AAC audio. Full decode and upright visual inspection passed.
This is not a claim of 30 fps or verified perceptual synchronization.

Three warm and three post-reboot probe opens each reached 300 frames, with first
frames under one second and clean release. Past genuine startup failures remain
unresolved; these six passes do not establish universal reliability or physical
cold-start success. Wake plus keyguard dismissal is needed before measuring an
app launch.

The latest sweep measured baseline luma ~17.4 and positive-compensation luma
32.6–33.3. Gain/ceiling changed from `0x200` to `0x3ff`; the sensor's own average
rose from `07` to `0d`. Integration and frame length stayed unchanged. All six
targets and the stock gain ceiling restored at zero; release took 2.313 seconds.
The image remains dark/noisy. A same-light phone comparison and lens-cover check
are unverified; the older lit-room photo is not a current lighting measurement.
Saved media and full startup regression have not been repeated on this image.

See [camera/README.md](camera/README.md) for the full implementation breakdown,
patch inventory, artifact hashes, failed approaches, evidence and build/test
runbook. Camera experiments were paused for this documentation checkpoint.

## Durable control and optional apps

```text
iPhone or Mac browser → remote service on Mac → authorized ADB → MIRROR
```

The Mac service starts at login and keeps the Mac awake while on external power.
It binds port 8765 on the trusted local network and opens without an access key.
Do not expose this unauthenticated control service to the Internet or an
untrusted network. Addresses are the observed setup, not guaranteed static IPs.

Controls include Back/Home/Recent, D-pad/OK, tap/swipe/text, volume, Sleep/Wake
and app shortcuts. Previews are snapshots, not live video. A complex screenshot
took about 13 seconds over Wi-Fi; the server allows 30 seconds and shares
concurrent captures. Wake dismisses a credential-free keyguard only when it is
showing. See [REMOTE-CONTROL.md](REMOTE-CONTROL.md).

Afterglow (`dev.mirror.clock` 0.1) was visually tested in both orientations;
portrait is remembered. It uses the Mac's port-8766 design server and bundled
assets when the live page fails. Home, relaunch, app menu, Sleep/Wake and the
offline fallback were tested. Installed clock APK checkpoint:
`56f4700dfd7c68f1bd9e49d03fdbfee1247f05adc21f6457361da46b966e9dc7`.

The optional dashboard (`dev.mirror.repurpose` 1.8.2) uses four-digit pairing
and its local API on port 8787. It is not the default launcher. Its pairing is
separate from the no-login Android remote.

## Wi-Fi, audio and storage recovery

The matching `pronto_wlan` module targets:

```text
3.10.49-perf-gf46dad5260f SMP preempt mod_unload modversions aarch64
```

Built by `mirror-build-running-kernel-wifi.sh`, its SHA-256 is
`3209948e50a290ede0939586762da074efcd7fbc55f325c84bc0fa680eba40fb`.
The Android Wi-Fi service retries driver loading for up to one minute because
the device node appears after framework startup. Automatic cold-boot
reconnection, Internet and DNS were verified.

Audio uses primary MI2S receive, both headphone outputs and the external-speaker
gate. Speaker playback was audible; a three-second microphone recording
contained live input.

The physical userdata partition is 5,583,458,304 bytes. The successful repair
used the local, ignored Android-6-compatible sparse image
`captures/adb-userdata-20260904/userdata-adb-raw-chunks.sparse`.
It was sent whole: the device reports a 256 MiB maximum download and this file
is approximately 155 MiB. These are checkpoint-specific observations, not
instructions to erase a currently working installation.

## Flash and diagnostic boundaries

- Early targeted work erased/reformatted only userdata and cache; reconstructed
  Android was subsequently written to system.
- Modern macOS `fastboot format:ext4 userdata` made filesystem features this
  Android could not mount, causing “Encryption unsuccessful.” Do not repeat it.
- Splitting the custom sparse userdata image with `fastboot -S 128M` caused a
  later chunk rejection; the successful repair sent that image whole.
- No bootloader, boot, recovery, modem, trust, GPT or board-specific firmware
  partition was replaced. Writes were scoped to verified serial `be9d0af`.
- Historical empty boot-dump files are not valid backups. Do not infer that a
  complete restorable factory image exists.
- Camera builders prepare images; they do not flash automatically. Preserve
  `MIRROR_CAMERA_FRONT=1` explicitly when rebuilding the current configuration.
- The CSI MMIO diagnostic can hang the board when idle/off/in an error state.
  Do not treat every read-only diagnostic as safe in every power state.
- Camera photos, room images, raw frames, logs, keys, vendor binaries and build
  images remain in ignored local storage, not in the public repository.

## Hardware facts

- Board: `MIR63A0-00-P1 / PCA#500240 RevP21`, Qualcomm APQ8016/MSM8916 family.
- No microSD slot; the display is output-only.
- Connected Molex `146153` dual-band Wi-Fi antenna.
- PCB `VOL-` during cold power-on enters fastboot; a blank panel can be normal.
- PCB `VOL+` enters signed recovery/update UI.
- Three-pin UART header: GND/TX/RX; treat as 1.8 V logic and never connect adapter
  VCC. UART is a diagnostic fallback, not the normal phone/Mac control path.
