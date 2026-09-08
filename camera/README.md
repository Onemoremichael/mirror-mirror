# Camera implementation and recovery guide

Checkpoint: September 8, 2026 device logs. This is the current camera guide;
[the lab log](../CAMERA-RECOVERY.md) preserves the full sequence of experiments.
The camera is **usable, but not finished**. All results describe the one tested
MIRROR, not every hardware revision or Android camera app.

## What works, and what does not

| Area | Verified result | Remaining boundary |
| --- | --- | --- |
| Hardware | One fixed-focus OV5640 front camera | No second/back camera |
| Preview | Coherent 720p and 1080p diagnostic frames; upright Snapcam photo/video preview | Image is much too dark; historical intermittent blank/invalid starts |
| Photos | Upright portrait JPEG saved and fully decoded | Exposure controls have not produced the expected brightness change |
| Video | Ordinary Snapcam 720p H.264 with AAC, upright and fully decoded | Software encoding, about 22.79 fps in the latest clip; not a guaranteed 30 fps |
| Rotation | FRONT/0 metadata, portrait desktop; correct preview proportions | Other third-party apps have not been exhaustively tested |
| Reboot | Raw recording property loads automatically; three post-reboot probe opens passed | Not proof of a physical cold-power-on recovery or universal startup reliability |
| Audio/video | Both tracks present and decodable | Perceptual synchronization not yet checked |
| Hardware encoder | Failure isolated from camera capture | Venus trusted-firmware initialization remains unresolved |

Android still opens Launcher3. The panel has no touch layer: use the Mac/iPhone
[remote](../REMOTE-CONTROL.md), which controls Android through authorized ADB.
Afterglow remains an ordinary optional app, not a launcher or automatic fallback.

## How the pieces fit

The original signed boot chain and Linux 3.10.49 kernel remain in place. The
replacement Android 6.0.1 Qualcomm HY22 userspace must match that kernel's
custom sensor and camera interfaces:

```text
OV5640 → stock sensor/CSI/ISP kernel drivers → adapted sensor library
       → Qualcomm daemon + compatibility hooks + CPP correction
       → Android camera HAL → Snapcam / diagnostic probe
                            → raw NV12 packing → software H.264 + AAC
```

Camera changes were delivered through the reconstructed `system` partition,
regular APK updates and temporary diagnostics. Camera work did not replace
boot, kernel, bootloader, recovery, modem, trust, GPT or board-specific firmware.

## 1. Getting the legacy stack to agree

The sensor reference source is pinned by `mirror-build-ov5640-camera.sh` to
Quectel SDK commit `ed0e50a102c7ee115c6999ba0a26ce50537c616e` in
<https://github.com/copslock/Quectel_sc20_linux_sdk>.

- `quectel-ov5640-hy22-abi.patch` removes later ABI additions to match HY22.
  Build checks require a 376-byte sensor structure and a 96-byte mode array
  (three 32-byte entries).
- `quectel-ov5640-hy22-modes.patch` and the `VFE_40` build definition establish
  the two-lane CSIPHY0/CSID0 path with `combo_mode=0`. Its early mode assumptions
  are subsequently corrected by the stock-mode patch below.
- `legacy-camera-compat.c` supplies optional fixed-focus hooks and translates
  the userspace 88-byte ISP input-configuration payload to the stock kernel's
  104-byte layout. The daemon receives this library as an added dependency.
- `mirror-patch-camera-cpp.sh` checks the input binary hash and branch bytes
  before making missing initial AEC statistics nonfatal. This YUV sensor has
  internal auto-exposure/white-balance rather than the expected separate
  Qualcomm statistics producer. The patch does not fix exposure quality.

These compatibility changes enabled progress but did **not**, by themselves,
produce valid images. Callback counts and CSI activity were insufficient proof.

## 2. Fixing the corrupt image at its source

Temporary C2D sampling showed corruption already present before color
conversion. This narrowed the fault; it did not establish a damaged sensor.
Bounded reads of named resident stock-kernel tables and disassembly then showed:

- kernel sensor modes 0 and 2 select its 1080p table; mode 1 selects its 720p
  recommendation table;
- register `0x4300=0x32` describes UYVY, while the replacement described YUYV;
- advertised 2592×1944 dimensions did not match the active stock mode.

`mirror-ov5640-stock-modes.patch` aligns the userspace description with those
stock modes and UYVY. That was the breakthrough to coherent preview and JPEG.
A requested 720p output may be scaled from a 1080p sensor mode; output size is
not proof of sensor mode. The 84 MHz 720p clock value remains inferred, not
measured. The earlier route-1 hypothesis was rejected.

The input sampler (`c2d-probe.c`, `c2d-loader-check.c`,
`decode-c2d-samples.mjs`, `mirror-build-c2d-probe.sh`) is retained for diagnosis
but **disabled in the current image**. Normal C2D and quiet processing logs are
restored; sample images and raw buffers are not tracked.

## 3. Startup and receiver timing

`mirror-ov5640-settle-probe.patch` retains a default receiver settle count of
`0x18`. The optional diagnostic override accepts the tested hex strings `14`,
`16` and `1a`; other values fall back to the default.

Experiments did not identify a universally reliable timing cure: `0x24` produced
two no-frame/error-100 outcomes; `0x18` passed five opens before a later failure;
`0x16` and `0x14` had mixed evidence. Some tests were confounded by cleanup.
Stopping preview can take about 40 ms, but full release took 1.6–4.6 seconds.
Wait for both `CAMERA_RELEASED` and an idle camera service before another open.
Do not repeatedly force-stop an actively releasing camera.

The bounded startup runner now removes stale reports, wakes Android, dismisses
the keyguard, waits for 300 frames, returns Home and checks release. Three warm
opens and three post-reboot opens passed, with first frames in 0.757–0.986 s.
An earlier dozing launch never called `Camera.open`; that is not a driver
failure. Genuine zero/invalid-frame starts have also occurred and are not
proven fixed. Android's media service can initialize the sensor before a
post-reboot test, so these are not physical sensor-cold-start measurements.

## 4. Making recording work without the hardware encoder

Venus hardware encoding failed independently with trusted-firmware metadata
errors (`scm -2`). Expected `venus.mdt` / `venus.b00`–`b04` files were absent
from the inspected `/firmware/image` mount. That observation is not an inventory
of every partition. Host firmware alternatives were not installed, and no
modem/trust partition was modified.

A synthetic I420 test proved software encoding could work. Real-camera
recording then exposed two separate problems:

1. The software path rejected camera metadata buffers (`Unsupported metadata
   type (0)`). `mirror-camera-raw-video.patch` adds a property-controlled raw
   CameraSource path.
2. The first raw attempt copied a padded 1,433,600-byte buffer into a tight
   1,382,400-byte allocation and crashed. That candidate is rejected.
   `mirror-codec-video-pack.patch` and `mirror-video-pack.h` copy only active
   NV12 rows from the exact known Venus allocation: stride aligned to 128,
   Y rows to 32, UV rows to 16, plus 20,480 bytes and 4,096-byte alignment.
   Unknown oversized layouts are refused rather than copied blindly.

Both 32-bit and 64-bit `libstagefright` are rebuilt; an initial 64-bit-only build
did not update the actual recording path. Host tests cover 720p, 1080p, 640×480,
642×482, invalid sizes, output bounds and padding with address/undefined-behavior
sanitizers. Those tests validate packing, not every possible camera layout.

`debug.mirror.video_raw=1` now comes from `build.prop` and was verified after
reboot without a manual setter. `mirror-snapcam-video-bitrate.patch` caps normal
720p H.264 at 4 Mbps on this Mirror configuration; it does not alter HFR/HSR,
time-lapse or all resolutions. Quiet diagnostic recordings reached about 26 fps;
the latest ordinary Snapcam recording reached about 22.79 fps. Do not present
diagnostic throughput as guaranteed app performance.

## 5. Correcting front-camera orientation and layout

There is only one physical front camera. Early BACK/0 and later FRONT/180
metadata were intermediate candidates. The user reported the latter upside
down and confirmed an explicit 90-degree preview as upright.

- `mirror-camera-metadata.patch` plus `mirror-camera-mount-correction.patch`
  produce the current **FRONT/0** HAL metadata when `ro.mirror.camera.front=1`.
- `mirror-snapcam-preview.patch` and `mirror-snapcam-video-preview.patch` fit
  photo/video previews using the sensor ratio and actual preview rotation,
  fixing the squeezed landscape strip on the portrait display.
- `mirror-snapcam-photo-rotation.patch`,
  `mirror-snapcam-photo-front-rotation.patch` and
  `mirror-snapcam-video-rotation.patch` provide saved-media orientation from
  display rotation when no orientation sensor supplies it. The photo correction
  removes front-preview mirror compensation from saved-photo rotation.

The native panel is 1920×1080; Android is locked to portrait 1080×1920 with
`user_rotation=3` and automatic rotation disabled. Current preview rotation is
90 degrees. Saved-video rotation is 270 degrees in the Android convention;
ffprobe reports 90 in its opposite-sign convention. Actual files were visually
checked upright. The preview is mirrored, while saved media is unmirrored.

Snapcam package: `org.codeaurora.snapcam`; activity:
`com.android.camera.CameraActivity`. Correct launch actions are
`android.media.action.STILL_IMAGE_CAMERA` and `android.media.action.VIDEO_CAMERA`.
The earlier action without `.action.` did not select video mode.

## 6. Brightness: the current investigation boundary

The user reports a very dark image. App exposure compensation at +2 EV (12
steps) and brightness 6 did not materially increase measured pixel brightness:
representative mean-luma comparisons were 23.93→23.68 and 18.44→18.47. We did
not persist ineffective brightening defaults or add sensor-register writes.

The read-only exposure diagnostic initially refused even live reads because the
custom sensor callbacks leave the generic `sensor_state` at zero. It now checks
the named CCI controller identity, sensor back-pointer, valid master, enabled
state and sole reference while holding the named OV5640 mutex. A closed camera
refuses I²C reads; live preview returned sensor ID `5640` and:

| Registers | Observation |
| --- | --- |
| `3500/3501/3502` | `00/45/c0`, later `00/3f/00`: substantial integration time |
| `3503` | `00`: automatic exposure enabled |
| `350a/350b` and `3a18/3a19` | `02/00`: gain at the configured ceiling |
| `380e/380f` | `04/60`: frame length |
| `3406`, `3a00` | `00`, `78` |
| `3a0f/3a10/3a1b/3a1e` | `30/28/30/26`: exposure targets |
| `5587/5588` | `00/01` |

The configured ceiling is **not** proof of the sensor's absolute maximum or
proof of hardware failure. Kernel command 25 is `CFG_SET_STREAM_TYPE`
(preview 0 / snapshot 1 / video 2), not initialization parameters. Reference
source forwards exposure via command 18, but the exact installed-binary path
has not yet been verified. Finding exposure tables in memory alone does not
prove they are selected at runtime.

The user supplied a phone photo from the same angle showing a lit room and
visible ceiling light; the Mirror comparison was much darker and noisier.
Phone HDR/exposure makes this an uncalibrated comparison, but it means we should
not dismiss the problem as simply an unlit room. A lens obstruction/cover check
is still unverified; no physical privacy shutter is assumed to exist.

Next pass: trace the installed exposure-control path, compare preview and saved
pixels under stable lighting, and establish whether the configured target/gain
limits or optical attenuation explain the mismatch before changing registers.
Also retain clean-release startup checks and eventually test a real cold boot.

## Evidence and installed artifacts

The most recent system image was flashed to `system` in 76.321 seconds and
Android reached `sys.boot_completed=1`. Hashes identify local checkpoints, not
a promise of bit-for-bit reproduction from this public repository alone.

| Artifact | SHA-256 |
| --- | --- |
| `system-mirror-final.img` | `d4f5b63c05ce814a1049a3a3858b9c1a3eb0e12bba7f8178e7ae339014af308a` |
| `SnapdragonCamera-mirror.apk` | `ba9c9c7a8da7122479ca30ca177ad0f49307796a78a8ed4dab4ba497429142da` |
| `libmmcamera_ov5640.so` | `8aa24b1b587fd834288b47852dd0314394dd64614210cec083b0949d632036b9` |
| `libmmcamera_mirror_haf.so` | `2bd59c15ca19d38c38ae880c64330bc1dc1ee3cda4629406f5732d18f0269a3c` |
| `mm-qcamera-daemon-mirror` | `3d2818e4d2fd5c77cc14d1d1d6c9882fcb342b62fa671263c3d0708303446d22` |
| `libmmcamera2_cpp_module-mirror.so` | `395b74bd284f93bef3f053f0fc2ffa36a7d428d0ffcab374904c705abc01fee9` |
| Camera HAL, 32-bit | `8aac22850afe19c224062840aa70e50d3bb4570f13bb4f8e091566aafdaa3eca` |
| `libstagefright.so`, 32-bit | `77c8c8b8b20287c4179dd44ec260410363e98716b11acf1158a3e963bdf9f5b8` |
| `libstagefright.so`, 64-bit | `e1eddb83afedb4fd660bad62b8df3a3b72f6311e3cca8650672144192688a625` |
| `mirror_camera_diag.ko` | `0218cfd6cea6260cf70e52c67f4d98938c07219cce53f897a239eaf61a407266` |

Selected private evidence (not published in Git):

- Upright JPEG `IMG_20260907_234207.jpg`: 271,597 bytes, 1080×1920, full decode.
- Prior Snapcam video: 795 frames / 38.692578 s (~20.54 fps), AAC, full decode.
- Latest 4 Mbps post-reboot video `VID_20260908_000505.mp4`: 7,961,433 bytes,
  413 frames / 18.1235 s (~22.79 fps), AAC 877 frames / 18.709333 s, full decode
  and upright visual inspection. Track-duration differences alone do not prove
  perceptual sync failure or success.
- Startup reports: `.work/camera-startup-1788826140497` and
  `.work/camera-startup-1788826394361`, three successful attempts each.

## Diagnostics and safety boundaries

`mirror_camera_diag.c` exposes three distinct interfaces:

- `/proc/mirror_camera_diag`: CSI MMIO. **Can hang the board when the camera is
  off, idle or in an error state.** “Read-only” does not make it universally safe.
- `/proc/mirror_sensor_tables`: bounded reads of named resident kernel tables.
- `/proc/mirror_sensor_exposure`: 20 fixed identity/exposure/gain/target register
  reads guarded by the controller checks above; no arbitrary register API.

The module is specific to the preserved kernel/configuration/symbol versions.
Exposure snapshots use `vmalloc` to avoid oversized stack frames; an earlier
`kmalloc` build generated GOT relocations unsupported by the stock module
loader. The builder rejects those relocation types. Do not load on another
kernel based only on a matching version number.

The probe app supports isolated preview, image statistics, JPEG/video tests and
explicit/automatic rotation. Reports and media are private. Keep only one camera
client active. Frame counts are not proof of good pixels, and a successful
encode is not proof of orientation, brightness, or audio synchronization.

## Build and test runbook

Prerequisites are local and ignored: the populated Android source/build ext4
image, matching HY22 vendor inputs, stock-kernel configuration and symbol
versions, Docker build environment (`alleen/apq8016_bm`), Android SDK/build tools
35, JDK 17 and local APK signing material. Source patches/scripts are tracked;
vendor binaries, images, signing keys and camera media are not. Do not run two
builders that mount the same build image concurrently.

From the repository root, prepare the camera layers in order:

```sh
./mirror-build-ov5640-camera.sh
./mirror-build-camera-compat.sh
./mirror-patch-camera-cpp.sh
./mirror-build-camera-diag.sh
./mirror-build-snapcam.sh
MIRROR_CAMERA_FRONT=1 MIRROR_VIDEO_RAW=1 \
  MIRROR_REBUILD_CAMERA_HAL=1 MIRROR_REBUILD_STAGEFRIGHT=1 \
  MIRROR_CAMERA_VERBOSE=0 MIRROR_C2D_PROBE=0 \
  ./mirror-build-final-system.sh
```

The matching Wi-Fi artifact must already exist (see the root README).
`MIRROR_CAMERA_FRONT` defaults to 0 in the generic builder: explicitly set 1
to retain this installation. `MIRROR_REPACK_ONLY=1` is only for an already
successfully built staging tree; it is not a clean-build shortcut. The Snapcam
builder updates the staged system APK as well as producing the standalone APK.
Final-image checks inspect both media-library architectures and property/HAL
markers. These commands build, **not flash**. Consult the recovery constraints
before any separately authorized, exact-device `system` write.

Host-only checks, without touching the Mirror:

```sh
node --check mirror-test-camera-startup.mjs
node --check camera/decode-c2d-samples.mjs
clang++ -std=c++11 -fsanitize=address,undefined -fno-omit-frame-pointer \
  camera/test-video-pack.cpp -o /tmp/mirror-test-video-pack
/tmp/mirror-test-video-pack
./mirror-build-camera-probe.sh
```

With the current probe APK installed and camera permission granted, an awake,
idle device can run the opt-in startup test:

```sh
MIRROR_SERIAL=be9d0af node mirror-test-camera-startup.mjs 3
```

Use the actual authorized Wi-Fi serial instead when USB is absent. This starts
the camera and writes private reports under `.work`; it does not change firmware
or upload images. It stops on release failures and returns Home. Inspect image
quality separately. A successful six-open sample does not close the reliability
issue. Do not automatically reopen the clock after tests.
