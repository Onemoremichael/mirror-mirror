# OV5640 camera recovery — historical experiment log

> **Checkpoint: September 8, 2026 device logs.** Read
> [camera/README.md](camera/README.md) for the current camera implementation and
> [RECOVERY-STATUS.md](RECOVERY-STATUS.md) for the installed system. This file
> preserves the experiment chronology, including failed and superseded
> candidates. “Current,” “next” and hashes inside older entries refer to that
> experiment, not the latest installation. Early BACK metadata, malformed
> preview, FRONT/180 orientation and manual raw-video setup are superseded.
>
> Current result: one FRONT/0 camera, usable upright preview/JPEG and decoded
> 720p H.264/AAC video. Severe darkness, historical intermittent startup,
> hardware encoding and perceptual A/V sync remain open. No full camera-quality
> completion claim is made.

## Initial September 6 result (superseded)

There is one physical front camera. Android enumerates one camera; the
replacement sensor library labels it BACK. That label does not indicate a
second physical camera.

Sensor discovery and parameter reads work. Earlier route-0 tests produced
substantial CSIPHY interrupt activity, little CSID progress and start-of-frame
timeouts. Later isolated-client tests below receive buffers in one mode, but
do not yet establish usable camera images or the exact remaining cause.

Earlier notes attributed the failure solely to ISP format selection and
recommended route 1. Subsequent tests moved past additional ABI/stream-on
failures and identified route 0 as the active receiver. Those earlier
conclusions are superseded.

## Reproducible changes

The sensor source remains pinned to commit
`ed0e50a102c7ee115c6999ba0a26ce50537c616e`.

- `quectel-ov5640-hy22-abi.patch` adapts the sensor-library ABI to the HY22
  binaries. The build checks a 376-byte sensor_lib_t and a 96-byte mode array.
- `quectel-ov5640-hy22-modes.patch` removes the unsupported VGA entry, retains
  2592×1944, 1280×960 and 1920×1080, and explicitly configures two CSI lanes,
  assignment 0x4320, mask 0x7, CSID/PHY 0, settle count 0x1b.
- The standalone sensor build now defines VFE_40, matching the normal Android
  build and selecting combo_mode=0. This alone did not restore frames.
- `legacy-camera-compat.c` supplies missing fixed-focus hooks and translates
  the old 88-byte ISP input-config ioctl payload into the kernel's 104-byte
  layout.
- `mirror-patch-camera-cpp.sh` checks the exact upstream library hash and branch
  bytes before adjusting the missing-initial-AEC error path. This is a narrow
  experimental change for a YUV sensor that handles AEC/AWB internally.

The installed sensor library was read back on September 6:

```text
/system/vendor/lib/libmmcamera_ov5640.so
SHA-256 e748793df9a7be7576bc94077012fa2ff8afa94564f8bb64925dd6cf6c20048a
```

Local evidence includes `.work/combo0-motion-logcat.txt`,
`.work/route0-motion-160x120-logcat.txt`,
`.work/route0-camera-dmesg.txt` and the earlier ioctl/CPP compatibility logs.
These raw logs are excluded from Git.

## Diagnostic module — deployed September 7

`mirror_camera_diag.c` exposes selected CSIPHY0/CSID0 registers and camera
device-tree properties at `/proc/mirror_camera_diag`. It performs no explicit
register writes. It is hardware-specific diagnostic code, not a camera fix;
live reads still require care about the receiver's powered state.

The previously prepared system image was flashed to `system` on USB serial
`be9d0af` on September 7. All four sparse sections completed successfully in
77.263 seconds. Android rebooted successfully, the module appears in
`/proc/modules`, and `/proc/mirror_camera_diag` is present. No userdata or
boot-related partition was written.

Two reads during the isolated 1080p stream show CSID total packet count at
offset 0x90 advancing from 0x12f19 to 0x242257. The ECC count at 0x94 remained
1 and CRC count at 0x98 remained 0. These offsets follow the local kernel's
`csid_v3_1` register map. The hardware version register reads 0x30030000;
the driver's configured version is 0x30010000. Neither that difference nor
the packet counts alone establishes the fault. The sensor's device-tree route
is PHY0/CSID0, assignment 0x4320, lane mask 0x3; live PHY power is 0xf and
settle registers are 0xd (the reference driver scales settle by clock ratio).

The preview still has a gray/noisy band and black remainder, despite 356
callbacks at 15 seconds. Packet reception is now directly evidenced, so the
next investigation should include ISP/CPP format, dimensions, and buffer
layout rather than assuming the physical receiver is producing no packets.
Local evidence: `.work/camera-diag-live-20260907.txt`,
`.work/camera-diag-live-second-20260907.txt`, and
`.work/camera-frame-after-diag-60.raw`. After capture, the probe was stopped
and Afterglow restored.

```text
Module: 4080cc59537e0935f3832ce02da98716c6af14bf8aff98ccea3561f890c2ef44
System: eedf1f328e0fab49c98425e394a0882141564b9c581e665a05fd0e8c3ce8d249
Vermagic: 3.10.49-perf-gf46dad5260f SMP preempt mod_unload modversions aarch64
```

Build order, with the local Android source image and matching kernel inputs
already available:

```sh
./mirror-build-ov5640-camera.sh
./mirror-build-camera-compat.sh
./mirror-patch-camera-cpp.sh
./mirror-build-camera-diag.sh
./mirror-build-final-system.sh
```

These commands prepare artifacts; they do not flash the Mirror. The current
system-image builder includes the experimental module and its boot-time load.

### Processing-log build, September 7

`MIRROR_REPACK_ONLY=1 MIRROR_CAMERA_VERBOSE=1 ./mirror-build-final-system.sh`
adds CPP/PPROC log level 3 (mask `805306375`) to staged `build.prop` and
verifies the setting in the generated filesystem. An earlier attempt to set
it from the post-boot script failed: SELinux denies `qti_init_shell` access to
`camera_prop`, even as UID 0. That failed logging image had SHA-256
`e9089d9c6cc8327ecf3cb890e59c25cd74f51e0df7c53cbb6cbdcadec7189868`.
The revised startup-property image was successfully flashed to `system` in
76.354 seconds and has SHA-256
`2b3f7b9159c3985b3155dd9532bd810e4e5d24734fc209d792daebc32fac194b`.
Sensor/CPP libraries are unchanged. The original diagnostic-only image is
retained locally as `system-mirror-diag-baseline.img`.

The revised property was verified on-device as `805306375`. The isolated
1080p run now emits detailed processing logs, saved locally in
`.work/camera-cpp-verbose-20260907.txt`. C2D reports input 2592×1944,
stride/scanline 2592/1944 and output 1920×1080. CPP reports input/output
1920×1080 with stride 1920 and scanline 1080. The reference C2D implementation
multiplies packed-YUV stride by two when creating its single-plane GPU surface;
the reported 2592 stride is therefore not by itself an error. Likewise the
sensor source deliberately doubles YUV output width and halves it for public
capabilities. No width patch is justified by those values alone. Next collect
input/output samples around C2D to separate sensor/ISP corruption from
conversion corruption. Probe stopped and clock restored after this pass.

## Isolated-client buffer checkpoint — September 6

The dashboard was repeatedly reopening the camera and competing with Snapcam.
Stopping both applications allowed a single-client test; Snapcam displayed
solid green, which is not evidence of a usable scene image.

The new `camera/probe` Android app records NV21 callback statistics and samples
in its private files. The saved local reports show:

| Preview / picture size | Result at 15 seconds |
| --- | --- |
| 640×480 / 2592×1944 | One nearly empty buffer; mean luma 0.0043 |
| 1280×960 / 1280×960 | Camera error 100; zero callbacks |
| 1920×1080 / 1920×1080 | 347 callbacks; mean luma about 43.64, sampled chroma ranges 0–10 |

Continuous callbacks at 1080p are progress, but these statistics do not prove
valid scene content or correct color interpretation. Raw reports remain local
under `.work/camera-probe-*-20260906.txt`; they are not published.

Follow-up inspection of the saved 1080p NV21 sample found a nearly uniform
gray band in the first 371 luma rows and black below, not a recognizable scene.
An alternate YV12 preview delivered four callbacks in 15 seconds; its first
buffer had constant luma 85. A recording-hint test delivered two callbacks,
with an all-zero first buffer. Both tests still selected kernel sensor `res=0`
(`ov5640_full_settings`), despite requesting 1920×1080. Neither test restored
usable imagery. Format-change messages from CPP alone are not a root-cause
diagnosis: the reference code logs a default-format warning before applying
its planar-format special case.

Build with `./mirror-build-camera-probe.sh`. Install the resulting
`artifacts/android-apps/camera-probe-debug.apk` with ADB, grant
`android.permission.CAMERA` to `dev.mirror.cameraprobe`, and launch
`.ProbeActivity`. Integer intent extras `width`, `height`, `pictureWidth`, and
`pictureHeight` select the test sizes; `zsl` defaults to `off`. String extra
`format=yv12` selects planar preview instead of NV21, and boolean extra
`recording=true` enables the recording hint. Samples use `.raw` filenames;
interpret them using the selected format and dimensions in the report.
Samples are cleared at each stream start to avoid confusing an old successful
sample with a new failed test. Read
`files/report.txt` with `run-as dev.mirror.cameraprobe`. Force-stop the probe
between tests, and keep other camera consumers stopped. This is a diagnostic
app, not the finished camera experience.

### Packed input sampling, September 7

`mirror-build-c2d-probe.sh` builds a temporary `libMD2.so` wrapper and checks
the exact source hash before changing the C2D module's library-load string.
The wrapper forwards `c2dUpdateSurface` to the original `libC2D2.so`; all
other lookup names resolve through that original dependency. A loader-only
test on the Mirror verified all eight required entry points. ARMv7 is explicit
to avoid an unavailable out-of-line atomic helper; that first build was not
deployed. `MIRROR_C2D_PROBE=1` opts into packaging the diagnostic wrapper.

The deployed sampling image is SHA-256
`838114f42fb6a213157cfbfebd603fe7bad75aefca4a386be9815ae4a59b50b8`;
the system-only flash finished successfully in 76.349 seconds. The wrapper
hash is `9a9f69236ba61b5875582650111d03b2c5fe91d1e4c5ee25a067160297921015`.
It samples only input calls 1 and 10, emits two 64×48 byte-parity grids to
local logs, and does not modify input pixels or the real conversion result.

Live input is format 120 (YUYV), 2592×1944, byte stride 5184. Both sampled
parities have irregular noisy/black bands rather than a recognizable scene.
The second sample's parities differ in 2419/3072 positions (mean absolute
difference 56.89); they are not identical copies. The application still
receives the malformed preview. This moves investigation upstream of C2D,
but does not exclude stale CPU cache views or incorrect buffer descriptions.
Do not conclude sensor hardware failure from these samples alone.

Evidence is local in `.work/camera-c2d-input-20260907.txt`; decode with
`node camera/decode-c2d-samples.mjs LOG OUTPUT_PREFIX`. Decoded files can
contain camera imagery and are not committed. Probe and log capture were
stopped and Afterglow restored after the test.

### Stream-interface trace, September 7

The compatibility library now logs at most twelve requests per selected ioctl
number, without modifying their payloads. The deployed system SHA-256 is
`69882d58787a46518bcdf8a07bace0ddbf990804fa407f7b3325edefdd4d4a4f`
(system-only flash completed in 77.410 seconds). Compatibility library hash:
`50894ff9eb0f40acf8086deaeb394a3dcc653aaadab1b57a367e0b7b2a16c7d8`.

Local log `.work/camera-isp-abi-20260907.txt` shows request `0xc09056c4`,
144 bytes: format `0x56595559` (YUYV), stream source 5 (RDI0), first plane
2592×1944, stride 2592, scanlines 1944, offset 0, CID 0, frame-based flag 1.
The input config is the already-translated 88-byte request with source 1,
CID 0 and frame-based flag 1. These values fit the reference kernel layouts;
this trace does not establish another ABI mismatch. Other devices reuse ioctl
numbers, so distinguish complete request values rather than just their low byte.

The three historical files named `mirror-stock-boot.img`,
`mirror-stock-boot-fetch.img`, and `captures/boot-stock-20260904.img` were
checked and are empty; they are not valid backups or sensor-table evidence.
No boot partition was written. Further sensor-table comparison requires a
verified source or a real readback. After this pass the probe/log reader were
stopped, Afterglow restored, Android boot verified and Wi-Fi retained.

### Stock mode correction and first recognizable preview, September 7

Read-only `/proc/mirror_sensor_tables` now exports bounded copies of named
resident stock tables and sensor configuration functions. Evidence is local
in `.work/stock-sensor-tables-20260907.txt` and the extracted `.bin` files.
The previously empty boot captures are not used as evidence.

The stock recommend table programs 1280×720 (line 1892, frame 740); the
1080P table programs 1920×1080 (line 2500, frame 1120). Disassembly of the
stock configuration function confirms mode 0 and mode 2 share the 1080P
table; mode 1 shares the recommend table. Both tables set register 0x4300
to 0x32 (UYVY), not the replacement library's YUYV description.

`camera/mirror-ov5640-stock-modes.patch` corrects that description and mode
dimensions. The 720p clock is provisionally 84 MHz; it is an inference, not
a measured clock. Installed system SHA-256:
`a66303031d49d8dcd0cd73f0b4b67cd7c69235a3b122fcd72a4fa9503ea1d426`.
Sensor library SHA-256:
`f03352be1ed6b9e85316124c5687784c987d0006671dc51df0d24245dbce941f`.
System-only flash completed in 76.368 seconds; Android boot completed.

The explicit 1920×1080 preview/picture test still failed to deliver usable
imagery. However, explicit **1280×720 preview, video and picture sizes with
ZSL off** produced a recognizable room image, verified by decoding the fresh
NV21 callback sample. It is dark/noisy but spatially coherent and colored.
The probe reached 900 frames in 31.655 seconds; its 15-second checkpoint was
421 frames. This is the first visually verified usable preview, not merely
a callback-count success. Evidence remains local, not committed:
`.work/camera-stock-720-frame60.raw`, `.work/camera-stock-720-report.txt`.
The first preview continued through 2700 frames in 92.966 seconds. A second
run saved a 143347-byte JPEG at 720p, visually verified as the same coherent
room scene, then reported `PREVIEW_RESUMED`. Local photo evidence is
`.work/camera-stock-720-photo.jpg`; its report is
`.work/camera-stock-720-photo-report.txt`. Probe defaults now use this 720p
configuration; optional `--ez photo true` captures after 20 seconds.
Camera-service restart/busy behavior was observed around stopping/replacing
the probe; retry succeeded, so lifecycle reliability is not yet established.
Consumer integration, longer stability testing, and removal of temporary
diagnostic logging remain. The probe was stopped and Afterglow restored.

## Next camera session

September 7 recording follow-up: 0x18 settling is **not yet fully reliable**.
After normal Snapcam use and a probe reinstall, a new 720p session produced
its first near-empty frame only at 35.340 seconds. Its receiver ECC register
was 0x112f1006, CRC 1 (`.work/camera-settle18-late-failure.txt`). A clean
reopen recovered coherent preview. The earlier five-start pass is real but
insufficient to establish reliability across app transitions.

The probe now supports `--ez video true`: a bounded 10-second 720p
CamcorderProfile recording, with microphone permission and recording hint.
It records privately to `files/video.mp4` and explicitly releases resources.
Good preview preceded `VIDEO_STARTED`, but stop failed and the output lacked
a valid MP4 moov atom. The repeat log `.work/camera-recorder-hint.log` identifies
`OMX.google.h264.encoder` error 0x80001001 and zero encoded video frames, while
447 audio frames encoded successfully. This is not a validated video file.
The Qualcomm encoder is listed in `/system/etc/media_codecs.xml` and its
32/64-bit libraries exist; investigate encoder selection and loading next.
Snapcam's shutter attempts produced no saved clip; app controls alone did
not establish a recording failure cause. The isolated test did.

Portrait orientation remains sideways. Temporary diagnostics have not yet
been removed. Afterglow was restored and camera capture stopped after this
pass. No firmware was changed during this recording follow-up.

Receiver comparison: `.work/camera-receiver-pass2.txt` captured a bad 720p
output session (first near-empty frame at 18.903 seconds). Compared with
the good receiver snapshot, lane/core configuration was unchanged. CSID
0x94 (ECC statistics in the reference register layout) was 0x074706d3 versus
0x00010000; packet count 0x90 was 0x00000e5b versus 0x000abba0. This supports
investigating receiver timing; it does not yet establish the exact electrical
cause. A controlled sensor-library experiment raises `settle_cnt` from 0x1b
to 0x24, leaving lane routing, format, clocks and dimensions unchanged.
With the previously observed divide-by-two clock scaling, expected programmed
settling count changes from 0x0d to 0x12. System-only flash completed in
76.430 seconds. Test image SHA-256:
`241d246f24eff17faf2a383a1d84d8e04db360a0875056d867136001da0cb15a`;
sensor library SHA-256:
`5f841d82a6803ac82541c8929dff7ca6ebeac9bd10e1f7df61f37c2db3f72d00`.
Runtime result: rejected. Two starts had zero frames and camera error 100.
The programmed count was verified as 0x12; packet counts were zero or nearly
zero. Evidence: `.work/camera-settle24-run{1,2}.txt` and corresponding
`receiver{1,2}.txt`. The next controlled experiment uses 0x18 (expected
programmed count 0x0c), slightly below the original 0x1b. It is not yet a
recommended setting. Do not read receiver MMIO after a camera error/release.

The 0x18 build has system SHA-256
`25158dda16f26d6fc7fee6245f3198124b5347e0557ea3bf90fcdf2ffc5ea300`
and sensor-library SHA-256
`3caad888d94bf07fbd527a10b712f946ba7f414feb2cd478d74a741dfa5f27e1`.
System-only flash completed in 77.430 seconds. **Promising verified result:**
five consecutive 720p session starts produced coherent frames (first frame
0.7–0.94 seconds), including the first start after reboot. Fresh frame 60 was
decoded and visually checked. Receiver snapshots 1 and 5 had ECC/CRC zero,
and the programmed settling count was 0x0c as expected. Local reports:
`.work/camera-settle18-run1.txt` through `run5.txt` and
`.work/camera-settle18-receiver{1,5}.txt`.

Full 1920×1080 output also now works: fresh NV21 frame 60 was visually
verified; a 337877-byte 1080p JPEG was saved and visually verified, followed
by continued preview through at least 900 frames. Evidence:
`.work/camera-settle18-1080-frame.raw`,
`.work/camera-settle18-1080-photo.jpg`,
`.work/camera-settle18-1080-photo-report.txt`.
This supports the shorter delay as a real receiver fix. Normal-app integration,
longer/cold-boot stability and removal of temporary diagnostics remain.
The installed Snapcam app was then opened with the standard still-camera
intent and its live room preview was visually verified in a screenshot
(`.work/camera-snapcam-settle18.png`). Orientation is sideways in portrait;
orientation metadata/consumer handling remains to be corrected. This was not
yet a Snapcam shutter or recorded-video test. Afterglow was restored afterward.

September 7 lifecycle follow-up: successful 720p output does **not** prove
the sensor itself ran in its 720p mode. Kernel messages during a good session
show `res =2 ov5640_1080P_settings`, and C2D logs show 1920×1080 input scaled
to 1280×720. Preserve the distinction between sensor mode and output size.

Repeated reopen tests still alternate between coherent ~29 fps streams and
almost empty, very slow buffers. Both media-service process IDs (255 and 294)
remained unchanged; historical binder-client death messages alone were not
evidence of service crashes. The test app now explicitly stops/releases in
`onPause`, reopens only while resumed with a valid surface, and logs
`CAMERA_RELEASED`. That cleanup was verified, but an empty-frame session
still occurred afterward. A subsequent reopen reached 600 good frames in
21.454 seconds. No firmware changed in this follow-up.

Screen/keyguard state is a separate confounder: waking without dismissing the
lock screen led to a ten-second timeout and Dozing. Wake plus dismissal restored
the activity; verify awake/unlocked before testing. Local evidence:
`.work/camera-lifecycle-20260907.log`,
`.work/camera-explicit-lifecycle-20260907.log`,
`.work/camera-reopen-receiver-20260907.txt` (good streaming receiver state),
and `.work/camera-lifecycle-good-report.txt`. Next compare the same receiver
registers during a bad session, rather than masking failures with app retries.

Preserve the working 720p mode, verify still capture and sustained operation,
and constrain camera consumers to the verified configuration before investigating
1080p separately. Keep the camera work separate from Afterglow: the
clock app does not access the camera or require new firmware.

### September 7: isolate recording firmware failure

A direct codec-only test (`--ez codec true` in the probe) fails to create
`OMX.qcom.video.encoder.avc` with error `0xfffffff4`, independently of the
camera. The software encoder can start in this isolated test, but the earlier
camera recording still failed with zero video frames. Kernel evidence in
`.work/camera-venus-failure-20260907.txt` explicitly reports Venus
`Invalid firmware metadata` and `Failed to load video firmware`. Merely
reordering codecs would not resolve this demonstrated hardware failure.

The original modem partition remains mounted read-only at `/firmware`.
An optional `MIRROR_FIRMWARE_AUDIT=1` build adds a startup inventory of only
`/firmware/image/venus.{mdt,b00,b01,b02,b03,b04}`: filenames, sizes and MD5s.
It does not modify the preserved partition. The bundled replacement MDT has
MD5 `ad3a81440f4b854e599672bdfd166303`. Comparing the original files is the
next gate before choosing a firmware-loading change; presence and usability
must not be assumed. Diagnostic image SHA-256:
`6ee940a19bda30f2bafd57743a3fdbb1ccf3cdf35301f641fef58955d70c6a8a`.

Audit runtime result: system-only flash completed in 76.544 seconds and
`sys.boot_completed=1`. All six queried original paths returned **No such
file or directory**, not permission denied. Evidence:
`.work/camera-stock-venus-audit-20260907.txt`. This rules out simply linking
those exact stock paths; it is not an inventory of every directory/partition.
The boot log still reports SCM call `0x2000201` returning -2 followed by
Venus `Invalid firmware metadata`. Reference `subsys-pil-tz.c` routes image
initialization through the trusted service, before segment loading.

The bundled MDT contains a `Generated Test Attestation CA` / `SecTools Test
User` certificate with HW_ID/OEM_ID zero. A host-only copy of upstream
[linux-firmware Venus 1.8](https://gitlab.com/kernel-firmware/linux-firmware/-/tree/main/qcom/venus-1.8)
has SHA-256 `f2089a12976b5c798a13742ff5bfea76521f114623c584052426ab0a5dc0870c`
and also contains test-signing certificate strings. It has **not** been
installed, and a newer/different file is not evidence of acceptance by this
device. The [postmarketOS firmware loader](https://gitlab.com/postmarketOS/msm-firmware-loader/-/blob/1.5.0/msm-firmware-loader.sh)
explicitly notes missing Venus files on many MSM8916 firmware partitions.
Next identify a matching vendor-signed source or further establish the
loader rejection reason before another firmware substitution. Receiver
startup intermittency remains a separate unresolved issue.

Per user preference, do not restore the clock between camera tests.

### September 7: bounded receiver timing comparison

After the firmware audit reboot, a baseline session delivered frame 1 at
901 ms and frame 300 at 11.656 seconds with nonempty luma/chroma ranges.
Reports are `.work/camera-audit-baseline-{report,receiver}.txt`. This is
another successful start, not proof the intermittent problem is fixed.

`camera/mirror-ov5640-settle-probe.patch` adds a temporary library-open hook
for `debug.mirror.camera_settle`. Only strings `14`, `16`, `1a` select
hexadecimal counts 0x14, 0x16, 0x1a; all other values (including empty and
`18`) retain 0x18. This nonpersistent diagnostic must be removed after
selecting a verified setting. Confirm actual programmed receiver registers
on every setting change: library caching or policy could prevent an override.
No automatic camera retry is introduced. Sensor library SHA-256:
`8aa24b1b587fd834288b47852dd0314394dd64614210cec083b0949d632036b9`;
system image SHA-256:
`df364d1629a8b1f32c7e66c37ec8fbe8e6c05c50bb6c341b90f0c84259684295`.

Runtime: system-only flash completed in 78.006 seconds; Android booted.
The override demonstrably changes the receiver without a daemon restart:
`16` programmed 0x0b; `14` programmed 0x0a. Four 0x16 starts delivered
frame 1 in 658–824 ms and frame 300 in about 11.4–11.6 seconds. Fresh
frame 60 from run 1 was decoded and visually verified. Reports and receiver
snapshots: `.work/camera-settle16-run{1,2,3,4}-{report,receiver}.txt`.
ECC/CRC snapshots were not uniformly zero; do not call this fully reliable.

The 0x14 comparison had three streaming starts out of four; run 3 instead
reported `OPEN_ERROR ... Fail to connect to camera service`, before preview.
Run 4 recovered without a reboot. Evidence:
`.work/camera-settle14-run{1,2,3,4}-report.txt` and
`.work/camera-timing-sweep-kernel-20260907.txt`. Tests used force-stop followed
immediately by open: possible asynchronous service cleanup is a confounder,
not proven receiver failure. The next test must explicitly allow onPause /
CAMERA_RELEASED and service disconnect before opening again, then separately
exercise abrupt client death. Current nonpersistent property is `16`; default
after reboot remains 0x18. Camera capture was stopped via Home then force-stop;
the clock was not restored.

Clean handoff follow-up: three 0x16 sessions passed after waiting for both
`CAMERA_RELEASED` and an empty active-client list before reopening. First
frames were 688–858 ms; each reached over 400 frames at the 15-second
checkpoint. Release became visible at poll 5 (one-second polling). Direct
in-app timing then measured stopPreview at 45 ms and total release at
1653 ms (`.work/camera-release-timing-20260907.txt`). Immediate force-stop /
reopen tests therefore include a real teardown confounder. They do not prove
the receiver itself fails on every such error.

The user reported forced landscape and a sideways camera image. The probe
now requests portrait, defaults to display rotation 270, and aspect-fits its
surface without stretching. A clear live screenshot verified upright content
at `.work/camera-portrait-fit270-success-20260907.png`. Raw buffers and JPEG
metadata are unchanged; this is a probe presentation correction, not yet a
system-wide HAL orientation/facing fix. A zero-rotation comparison was
visibly sideways and rejected. Another 270-degree open had zero frames at
15 seconds; a clean reopen recovered. Evidence:
`.work/camera-portrait270-failed-open.txt`. Thus waiting for handoff does NOT
establish full startup reliability, and the goal remains unfinished.

### September 7: software encoder buffer mismatch identified

Probe `--ez codecBuffer true` encoded 30 synthetic I420 frames at 1280×720
through `OMX.google.h264.encoder`, muxing one second of H.264 into MP4.
Result: sent=30, written=30, EOS=true, elapsed 2349 ms, 28230 bytes.
Host ffprobe counted all 30 frames; ffmpeg decoded the entire file without
errors. This proves ordinary-buffer encoding works, NOT real-time throughput
or camera/audio recording. Evidence:
`.work/camera-software-codec-buffer-20260907.{txt,mp4}`.

A subsequent real camera recording reproduced the precise error:
`SoftVideoEncoderOMXComponent: Unsupported metadata type (0)`, followed by
`SoftAVCEnc: Error in extractGraphicBuffer` and ACodec 0x80001001.
Evidence: `.work/camera-software-metadata-20260907.log` and
`.work/camera-metadata-failure-report-20260907.txt`. This separates the
software recording failure from the independent Venus firmware rejection.
One intervening attempt had no preview frames and correctly declined to
record; do not count that as an encoder test.

`camera/mirror-camera-raw-video.patch` adds a narrow opt-in property
`debug.mirror.video_raw=1` to CameraSource before metadata negotiation.
It requests ordinary pixel buffers rather than legacy camera metadata.
`MIRROR_REBUILD_STAGEFRIGHT=1` applies the patch idempotently inside the
build image and rebuilds libstagefright before repacking. Patch dry-run and
shell syntax checks passed; build started. No image with this recording
change has been flashed or tested yet. Validate both installed architecture
libraries, the runtime log marker, camera recording, decoded frames, audio
synchronization and performance before calling it a fix.

Build follow-up: the first `libstagefright` target rebuilt only lib64 (make
succeeded in 3:43), not the 32-bit library used by the running mediaserver.
No recording-change image was flashed. The wrapper also exited with a shell
EOF error after repacking because its source was edited during execution;
do not edit a running shell script in place. Current script passes `bash -n`.
The build now requests both `libstagefright` and `libstagefright_32`, uses
pipefail to propagate compiler errors through tee, and checks the test-property
marker in both libraries inside the completed image. A fresh build is running.
Shell can set/read `debug.mirror.video_raw=1`; that alone does not prove the
current (unpatched) runtime uses it. Reboot clears this diagnostic property.

The corrected two-architecture build succeeded (3:41 for media build,
19 seconds for repack). Both inspected libraries contain the diagnostic
property marker. Image SHA-256:
`3d633cbb71434cd5fa1aacf24104eb290ace24537c9dd77d27d5720af22c6083`.
libstagefright SHA-256: 32-bit
`9714716cf375ca47be9bf6d7e30d99ec625a788913ab6f80fef4dfb925774106`,
64-bit `8932a4de1cc9b0bfa71974777b1e1f266350e17be1e08ccc0e40b3b1a124b594`.

Runtime raw-video experiment: system-only flash completed in 76.433 seconds,
Android booted, and CameraSource logged the raw-buffer marker. Healthy preview
preceded VIDEO_STARTED. The metadata error disappeared, but mediaserver then
SIGSEGV'd in `MediaCodecSource::feedEncoderInputBuffers()` / `memcpy`; the
camera reported error 100. A misleading VIDEO_SAVED callback left only 3227
bytes, with no MP4 moov atom. This is a failed recording, not success.
Evidence: `.work/camera-raw-video-{test,crash,report}-20260907.*`.

Reference MediaCodecSource.cpp copies `mbuf->size()` directly into the encoder
input without a capacity check (line 612). Crash r8=0x15e000 (1433600 bytes);
the destination start/fault-address difference is 0x151800 (1382400 bytes,
exactly tight 1280×720 YUV420). Qualcomm's reference video allocation uses
VENUS Y/UV stride, scanline and buffer-size macros, while CameraSource declares
width/height as stride/slice-height. This supports a padded-versus-tight
buffer mismatch; verify the exact plane layout before implementing a packer.
The next fix must check bounds and pack the actual planes, not truncate blindly.

`debug.mirror.video_raw` was reset to **0** after the failure. The media service
restarted automatically (259 → 2024). Capture has ended. Default behavior is
unchanged unless explicitly opted in; full camera functionality is not achieved.

The TimStewartJ repository provides an application-level camera consumer and
retry behavior, but the reviewed implementation did not supply a replacement
HAL/kernel fix for this receiver issue.

### Checked recording-buffer conversion (2026-09-07, validation in progress)

The reference linear NV12 Venus allocation exactly matches the crashing input:
128-byte row alignment, Y rows aligned to 32, UV rows aligned to 16, plus
20,480 padding/extradata bytes and a final 4096-byte alignment. Added
`camera/mirror-video-pack.h` to copy only active Y/UV pixels into a tight
encoder input, preserving UV order. The AVC software encoder explicitly maps
YUV420SemiPlanar to `IV_YUV_420SP_UV`.

`camera/test-video-pack.cpp` passes AddressSanitizer/UndefinedBehaviorSanitizer
at 1280×720, 1920×1080, 640×480 and 642×482. Tests check every output pixel,
tail sentinels, rejected source sizes, and insufficient destination capacity.
These synthetic tests do not establish correctness of actual camera frames.

`camera/mirror-codec-video-pack.patch` integrates the conversion in
MediaCodecSource, gated by `debug.mirror.video_raw=1`, video/nonmetadata input,
and the source's NV12 color format. Unknown oversized buffers fail with an
error instead of overflowing encoder memory. Both architecture builds are
required. Device recording validation is pending.

The user's repeated landscape-at-launch report was checked against Android:
auto-rotation was enabled, default user rotation was 0, and WindowManager
reports this panel's portrait rotation as 3. Set user_rotation=3 and disabled
auto-rotation to retain portrait outside the probe. This does not correct
the camera HAL's facing/orientation metadata or saved media orientation.

Checked conversion build passed for both architectures (3:50 media build,
21 seconds repack). Image SHA-256:
`5606aac492cc8f51f7955355ab750fe8bb86a82cfcd7ee2ab8c4d936c44f3b34`.
32-bit libstagefright SHA-256:
`77c8c8b8b20287c4179dd44ec260410363e98716b11acf1158a3e963bdf9f5b8`;
64-bit: `e1eddb83afedb4fd660bad62b8df3a3b72f6311e3cca8650672144192688a625`.
The probe now reports `VIDEO_FINALIZED_UNVERIFIED` rather than `VIDEO_SAVED`
after stop; a successful stop callback is not media validation.

Runtime result: system-only flash completed in 76.191 s; Android booted and
retained portrait settings (3, auto-rotation off). With raw video enabled and
settle=16, healthy preview preceded recording. Mediaserver remained PID 259;
the camera released cleanly and active clients were empty. The 8,789,109-byte
MP4 contains 146 H.264 1280×720 frames (8.844 s, ~16.5 fps) and 453 AAC frames
(9.664 s). ffmpeg decoded the complete file with no errors. A sampled frame
shows coherent room content without plane corruption, but remains sideways.
This establishes a working recording path, NOT full functionality: frame rate,
unequal track end times, orientation, cold-start reliability and default app
integration remain unresolved. Evidence stays private under
`.work/camera-packed-video-{test,report,frame}-20260907.*`.

Second pass kept 720p and changed only requested bitrate (14 Mbps → 4 Mbps)
plus a 270-degree recording orientation hint. The 3,134,264-byte MP4 contains
176 H.264 frames over 9.011 s (~19.5 fps), with 455 AAC frames over 9.707 s.
Full ffmpeg decoding passed again; automatic display-matrix rotation yields
an upright portrait image. The frame-rate improvement is one paired result,
not a repeatability claim, and neither run establishes audiovisual sync.
Evidence: `.work/camera-packed-video-4m-20260907.{mp4,log}` and
`.work/camera-packed-video-4m-frame-20260907.png`.

Recording performance follow-up: all four CPU cores are online; the software
encoder supports up to four and uses its normal speed preset. Verbose pproc
logging remains enabled at 805306375. An attempted shell change to 0 did not
take effect (verified unchanged), and adbd cannot run as root under the
preserved boot configuration. Do not assume the diagnostics were disabled.
A quiet system repack is the next controlled overhead test; avoid changing
CPU clocks or unrelated firmware. Raw video is still opt-in and resets at boot.

### Quiet processing comparison (2026-09-07)

Repacked with MIRROR_CAMERA_VERBOSE=0 and MIRROR_C2D_PROBE=0, retaining the
same sensor and checked media libraries. Image SHA-256:
`17819f4445859dc19257af300825d9ac0d0d13a758511c7333f72049b4531b0f`.
System-only flash completed in 76.409 s. Android booted; pproc debug mask is
now absent (verified), and the live 32-bit libstagefright hash remains
`77c8c8b8b20287c4179dd44ec260410363e98716b11acf1158a3e963bdf9f5b8`.
Re-enabled diagnostic raw video=1 and settle=16 for the comparison.

First open after reboot had zero preview frames, so recording did not start.
It released in 1869 ms; an empty active-client list was verified before retry.
This preserves evidence of a cold-start failure rather than silently treating
the retry as reliable startup. Report: `.work/camera-quiet-cold-open-20260907.txt`.

Two subsequent 720p/4 Mbps captures completed and fully decoded without errors:

| Capture | Video frames / duration | Average fps | AAC frames / duration |
| --- | --- | --- | --- |
| quiet retry | 239 / 9.145533 s | 26.07 | 448 / 9.557333 s |
| quiet repeat | 240 / 9.145211 s | 26.24 | 447 / 9.536000 s |

Both remain portrait-metadata clips. Evidence:
`.work/camera-quiet-video-4m-20260907.{mp4,log}` and
`.work/camera-quiet-video-repeat-20260907.{mp4,log}`. Full decode is not proof
of perceptual audio/video synchronization; track lengths still differ by
roughly 0.4 seconds. These paired tests support diagnostic overhead as a
performance contributor, not a sole explanation. Mediaserver survived and
the camera is released. Keep this quieter build for further work. Remaining
work includes reliable first open, ordinary-app facing/orientation, persistent
recording integration, still-capture regression, and audiovisual validation.

### Startup command-path investigation (2026-09-07, in progress)

Upstream Linux's `ov5640_set_stream_mipi()` writes 0x300e as well as 0x4202;
its power setup explicitly establishes idle LP11. Source:
https://github.com/torvalds/linux/blob/master/drivers/media/i2c/ov5640.c
(reviewed September 7). The Quectel reference userspace library only has
0x4202 in start/stop tables, while the preserved kernel has its own built-in
start/stop paths. This is a hypothesis about receiver synchronization, NOT
evidence that adding a particular register write fixes this board.

Added a bounded leading-command trace for V4L2 private ioctl 193, including
resolved fd path and payload size, to distinguish sensor controls from other
controls sharing that ioctl number. It records no images and does not follow
embedded pointers. The first build hit the old NDK's incompatible ioctl
declaration in unistd.h; corrected by declaring readlink without changing the
existing ioctl hook ABI. Only the subsequent successful build is being tested.
Compatibility library SHA-256:
`c18332c5f3094c470fde30a3939f43b7aa403bb714431b2ae631e30b2c0089fc`.
Trace image SHA-256:
`087178786148f2511d4f963371ab0c03a80bdf2e5df5fb2a216f37c0e6c30cb4`.
Current sysfs maps v4l-subdev6 to ov5640; confirm mappings after reboot.

Trace image flashed successfully (77.881 s), booted, and produced healthy
preview: 402 frames at 15 s. Runtime path=/dev/v4l-subdev6 is confirmed ov5640.
The binary sends cfgtype 5/10 (power up/init), then 12/25/11 (stop stream,
stream type, resolution), then 13 (start stream). Command 25 was initially
misidentified as init parameters; the later kernel audit corrected it to
CFG_SET_STREAM_TYPE. It does not use the
Quectel reference's CFG_WRITE_I2C_ARRAY start/stop path. Therefore editing
the reference library's start/stop register arrays would not address this
runtime. Follow the preserved kernel's built-in tables instead.

Important correction to prior "cold-open" labels: before the test activity,
the sensor trace shows an initial power-up/init/power-down cycle, and camera
service history identifies a `media` client (PID 255), not the probe. The
reason for that system-client cycle is not yet established. The first *probe*
open after boot is not proven to be the sensor's first initialization.
Do not attribute this cycle to the dashboard without evidence.

Evidence: `.work/camera-sensor-startup-20260907.log`. Camera released and
active clients are empty. The trace also caught CPP controls sharing ioctl
193; source is now narrowed to the observed 144-byte sensor payload so future
builds will not spend the trace budget on CPP frame commands. That narrowing
is not yet installed. No sensor register behavior was changed in this pass.

### Actual stock stream tables (2026-09-07)

Extended the read-only symbol dump to include the named start/stop/AEC tables.
Image `e17e8d84792bfa92c51c14b5e13b3f8323fb55fd624794dde1df1f2a17461d1b`
flashed system-only in 76.446 s and booted. The module hash is
`f12b945f006a94e456b763fa8a11fe7e8eb5106406dfae8622b754cec511f0d0`;
the narrowed compatibility trace hash is
`2bd59c15ca19d38c38ae880c64330bc1dc1ee3cda4629406f5732d18f0269a3c`.

The preserved driver uses one 16-byte entry each: start writes 0x3008=0x02;
stop writes 0x3008=0x42. Mode initialization already writes standby and
0x4800=0x24. Thus the earlier hypothesis based on a 0x4202-only reference
stop table is not applicable to this runtime. No redundant standby write
was added. AEC enable is 0x3503=0, 0x3406=0; disable is 0x3503=7, 0x3406=1.
Raw evidence: `.work/stock-sensor-stream-tables-20260907.txt`.

Ordinary-app orientation follow-up: installed `/system/lib/hw/camera.msm8916.so`
exports QCamera2Factory::getCameraInfo and matches the reference factory path
that delegates to QCamera2HardwareInterface::getCapabilities. Android still
reports BACK/0 degrees. Before changing the reported mount angle, measure
the application's actual Display rotation rather than inferring it solely
from panel/native dimensions or screenshot orientation.

Probe measurement confirms Display rotation=3 while the empirically upright
preview uses setDisplayOrientation(270). Preview produced fresh frames (first
at 767 ms, frame 60 at 3132 ms). This supplies the actual display-rotation
input for evaluating a HAL-facing/mount-angle correction. Camera metadata
has not yet been changed. Closed the probe after measurement.

### Front-camera metadata test (2026-09-07, build in progress)

Added `camera/mirror-camera-metadata.patch` at QCamera2Factory::getCameraInfo.
It is enabled only by `ro.mirror.camera.front=1`, successful capability lookup,
camera ID 0, and exactly one detected camera. The candidate reports FRONT/180.
This is derived from measured Display rotation=3 (270 degrees), verified
upright setDisplayOrientation(270), and the standard front-camera formula
in frameworks/base/core/java/android/hardware/Camera.java. It is not an
assumption that all front cameras mount at 180 degrees.

The probe's new `autoRotation=true` option uses that standard formula and logs
CameraInfo, allowing a check independent of the prior hard-coded display
rotation. Build with MIRROR_REBUILD_CAMERA_HAL=1 and MIRROR_CAMERA_FRONT=1.
The front override defaults off in the builder until validation; subsequent
repacks must specify it explicitly to retain the test. This metadata-only
change does not fix intermittent startup, sensor programming, or hardware
encoding. Verify in Snapcam as well as the probe before accepting it.

Build target correction: `camera.msm8916` is not a make target in this
64-bit product; the existing HAL is a 32-bit secondary-architecture module.
The builder now requests `camera.msm8916_32`. The failed first attempt did
not install any image. The diagnostic APK with autoRotation installed
successfully; it still defaults to the previously tested fixed rotation
unless autoRotation is explicitly requested.

Storm pause/resume: the corrected HAL target compiled successfully (3:45),
but packaging was interrupted for the requested power-down. After reconnect,
repacked without recompilation, with MIRROR_CAMERA_FRONT=1. Filesystem checks
verified both the property and the HAL marker before system-only flashing.
Candidate image SHA-256:
`6e3f9555478e1c39b3a556da75ae8b3d2e9db755c524ca90b7f3b1fe23a52ba1`.
HAL SHA-256:
`c4ecdd73926766d243bc404ff17dc0070f084f7c8cd31f1350b1a13c20f35740`.
Runtime orientation and ordinary-app behavior still require validation.

Runtime result: system-only flash completed in 77.834 seconds, reboot completed,
and CameraService reports exactly one FRONT/180 camera. Probe autoRotation
computed 270 from Display rotation 3, without using its fixed-angle override.
720p delivered frame 1 at 738 ms and frame 60 at 3143 ms; a separate 1080p
open delivered frame 1 at 1050 ms and frame 600 at 26411 ms. Snapcam also
displayed live imagery, but squeezed it into a wide strip on the portrait
screen. The scene was too dark to conclusively verify upright orientation.
Requested a lit upright reference from the user; do not mark visual validation
complete based only on the numerical formula.

Reflection: the metadata correction is observable and does not prevent live
preview in these tests, but it does not fix ordinary-app layout. SnapdragonCamera
PhotoModule.setPreviewFrameLayoutCameraOrientation enables a special resize path
for mount angles divisible by 180. PhotoUI.setAspectRatio/layoutPreview then
uses configuration orientation and raw Display rotation to size/swap the surface;
this is a likely source of the native-landscape Mirror's squashed portrait
preview. No camera-app layout patch has been installed yet. Preserve the
distinction between HAL metadata, surface aspect ratio, actual image rotation,
mirroring and saved-media orientation. Intermittent zero-frame startup, persistent
video configuration and hardware-encoder firmware remain separate work items.
Evidence is private in `.work/camera-front-auto*-20260907.*` and
`.work/snapcam-front-20260907.png`. Closed the diagnostic camera after testing;
did not restore Afterglow.

### Snapcam photo-preview layout pass (2026-09-07)

Added `camera/mirror-snapcam-preview.patch` and `mirror-build-snapcam.sh`.
On the Mirror property only, PhotoUI now fits the unmodified sensor aspect
ratio after applying actual preview rotation. Other devices retain existing
layout. The patch cleanly reverse-checks against the modified reference source;
portrait/landscape fit arithmetic checks passed. Build completed in 4:04.
APK SHA-256 `e3ec90a8dff9d47c98f71c8915933f42cd08c54301915cdadca56d916879dc8c`.
Installed successfully as an update to the existing platform-signed Snapcam,
without another system flash. Build staging also contains this APK for future
repacks. Runtime logs show `Mirror preview fit 1080x1920 rotation=270`;
`.work/snapcam-fit-20260907.png` verifies removal of the squeezed wide strip.

The visible shutter control produced `/sdcard/DCIM/Camera/IMG_20260907_223011.jpg`,
154120 bytes, 1920x1080, fully decoded by ffmpeg. Private local copy:
`.work/snapcam-capture-20260907.jpg`. Its displayed image remains landscape
relative to the portrait preview and sips reports no orientation field;
saved-photo orientation needs investigation, not a claim of completion.
VideoUI has a separate analogous layout path and is not patched by this pass.
Closed Snapcam and verified no active camera client afterward. No clock restore.

Reflection: fixing the surface dimensions corrected one independently verified
app defect. Capture works in the regular app, but photo orientation, video UI,
recording defaults, intermittent startup and final lit-scene checks remain.

### Saved-photo orientation investigation (2026-09-07)

`dumpsys sensorservice` reports no sensors. PhotoModule initializes mOrientation
to ORIENTATION_UNKNOWN and CameraUtil.getJpegRotation returns zero in that case.
Direct JPEG EXIF parsing confirmed the first saved photo has an EXIF block but
no orientation tag. Added a Mirror-only, unknown-orientation fallback in
PhotoModule for both capture and setFlipValue. First candidate reused preview
rotation 270. APK `d3f5aa045670a9ec56e66b7878dc656e567e70996dedf4e077c6a63dccf84e08`
built and installed, and capture logged rotation=270. Result JPEG
`IMG_20260907_223837.jpg` is 194640 bytes, 1080x1920, fully decodes, but visible
features are vertically reversed relative to the preview. This candidate is
not a completed orientation fix. Private evidence:
`.work/snapcam-capture-rotated-20260907.jpg`.

Reflection: preview mirroring means display orientation cannot simply be reused
as saved JPEG rotation. Next candidate undoes the front-preview mirror
compensation, yielding 90 instead of 270 on the current portrait display.
It should preserve upright orientation with a horizontally unmirrored saved
image; verify against actual preview features rather than dimensions alone.

Second photo candidate built (APK SHA-256
`ede1174e07fae889ce5601fa362cda0111a9cef9f628a41fe7989888bc5bf8b3`)
and installed; logged saved rotation 90 and produced
`IMG_20260907_224446.jpg` (275654 bytes). Before accepting orientation,
the user explicitly reported the visible image is upside down. This overrides
the prior inferred upright baseline: preview 270 is NOT physically upright.
The FRONT/180 mount candidate is therefore not validated. Launched diagnostic
preview with explicit rotation 90 (180 degrees from prior preview) for user
confirmation. If confirmed, FRONT/0 metadata yields 90 at Display rotation3;
the saved-photo fallback undoing front mirroring would then yield270.
Do not fix the whole desktop rotation to compensate for the camera.

### Video-preview layout preparation (2026-09-07)

While awaiting physical confirmation of the explicit 90-degree probe preview,
added `mirror-snapcam-video-preview.patch` and its builder integration. VideoUI
now retains the actual sensor ratio in both size setters and fits it using
the actual preview angle on Mirror only, analogous to the tested PhotoUI fix.
Inspected the patched build source to verify insertion locations. Build passed
in 4:00; APK SHA-256
`b1f22de4fad4880980813d654f2ae11999106561e5c073cdf7879df57b19f384`.
This is compiled evidence only until video UI is launched and visually tested.
The diagnostic preview remained active and delivering frames throughout the
build; no permanent HAL mount-angle change was made without confirmation.

### Confirmed upright angle and low-light controls (2026-09-07)

User confirmed explicit preview rotation 90 is upright and reported that the
image is much too dark. Corrected the HAL override to FRONT/0 via
`mirror-camera-mount-correction.patch`. System-only image
`7f78782972e8a1fd8bad1f0d98333bc0a66c715d39cd3464295b925508b1b21d`
built, passed filesystem marker/property checks, flashed in 76.301 seconds and
booted. CameraService now reports FRONT/0 and probe autoRotation computes90.
This supersedes the rejected FRONT/180 assumption. Desktop rotation unchanged.

Added optional bounded probe extras `exposure` (advertised min/max) and
`brightness` (0..6, luma-adaptation), with logged requests and pixel statistics.
Current scene tests: baseline EV0 frame600 mean Y=23.93; requested+2EV (12steps)
frame300 mean Y=23.68; brightness6/EV0 frame300 mean Y=22.60. All delivered
live frames but neither control materially brightened the image. The scene is
not a calibrated fixed-light test, so these measurements support an ineffective
control path rather than proving its precise cause. Reports are private:
`.work/camera-exposure0-20260907.txt`, `camera-exposure12-20260907.txt`, and
`camera-brightness6-20260907.txt`.

Reflection: do not persist these ineffective settings or confuse screen
brightness with sensor exposure. Investigate actual sensor AEC/AGC initialization,
runtime forwarding of exposure requests and gain/shutter limits. Quectel source
has SENSOR_SET_EXPOSURE_COMPENSATION forwarded to CFG_SET_EXPOSURE_COMPENSATION,
but installed binary behavior still needs verification. AEC enable/disable tables
exist in the preserved kernel; that alone does not prove when they execute.
Closed diagnostic after testing. Saved-photo/video orientation must be retested
with the corrected metadata; video orientation fallback remains unimplemented.

### Live exposure diagnostic, not yet yielding registers (2026-09-07)

Added `/proc/mirror_sensor_exposure` to the read-only module. It looks up only
the named stock OV5640 control/mutex, verifies compile-time I2C-client offset2856
and stream-type offset2960 against stock disassembly, checks the expected CCI
read function and address width, takes the sensor mutex, and reads a fixed list
of twenty ID/exposure/gain/target registers only when sensor_state says powered.
No register-writing path was added. Initial oversized stack allocation was
caught by the build and moved off-stack. kmalloc's generated GOT relocations
were rejected by the stock loader (unsupported RELA311); replaced with vmalloc
and added a builder rejection for GOT relocations. No such relocations remain.

Installed system `8c9663f62828a45d7655cc7810f80c1265b3158f05a77ec48666028eb8ec6bb0`,
module `6b739d40ce72e1c77f50768037407cc1b3b4b7bc9dbf9b911904b8baf1cd7862`.
Module loads successfully. Proc returns `Sensor not powered; no I2C reads
attempted` both with camera closed AND while a verified live probe delivered
600frames. Therefore no sensor register readings were obtained. Do not remove
the guard to force reads: verify whether this custom driver maintains
sensor_state, and establish an authoritative powered/streaming guard first.
Camera remained functional and was closed after testing.

Important interpretation correction: sensor command25 is CFG_SET_STREAM_TYPE,
not sensor init parameters. Kernel stream enums are preview0/snapshot1/video2.
Stock start-stream code branches on the stream-type field before choosing an
AEC enable/disable table. The actual scalar value and table identity must be
verified before blaming snapshot-mode selection. Source enum values and mere
presence of AEC tables do not establish runtime exposure behavior.

### Exposure readings obtained; darkness not yet fixed (2026-09-07)

Stock custom power callbacks bypass the generic handler that maintains
sensor_state. Replaced that stale-field guard with named `msm_cci_get_subdev`
identity, subdevice/back-pointer validation, valid master, enabled CCI state and
exactly one reference, under the named OV5640 mutex. All reads still use the
stock I2C read function; no arbitrary addresses or register writes were added.
Built module `0218cfd6cea6260cf70e52c67f4d98938c07219cce53f897a239eaf61a407266`
without GOT relocations; system-only image
`d12c904b42917cf6c64b688f19107be5bb4be1760da9891551da136c3a771332`
flashed successfully in 77.868s. Android boot completed. Closed-camera check
reports CCI state1/references0 and refuses I2C; live check reports state0/ref1
and correctly reads chip ID 0x5640. After clean release it again refuses reads.

First preview after reboot produced only two invalid frames (the known startup
failure); the next open produced coherent frames. Stable EV0 preview frame60
mean Y=18.44. Its registers and the next +2EV preview's registers were identical:

```
stream_type=0 sensor_state=0 (stale) cci_state=0 references=1
3500/3501/3502 = 00/45/c0    3503=00
350a/350b = 02/00           3a18/3a19 = 02/00
380e/380f = 04/60           3406=00  3a00=78
3a0f/3a10/3a1b/3a1e = 30/28/30/26
5587/5588 = 00/01
```

+2EV preview frame300 mean Y=18.47, with 408 frames by 15s. Thus the requested
exposure compensation did not change these sensor targets/gain/shutter values
or materially brighten pixels. Automatic exposure is enabled; gain equals its
configured ceiling and shutter is near frame length. Do not conflate the gain
ceiling with the sensor's absolute hardware maximum. A failed first stream had
different limits/targets; do not use that as the baseline for valid frames.

Reflection: darkness could involve low incident light through the glass and/or
inadequate exposure limits; measurements do not settle that distinction. Asked
user whether room is well lit. Do not persist ineffective EV settings or claim
brightness fixed. Current diagnostic preview remains open at requested +2EV
for a lighting check; ordinary-camera defaults were not modified. No clock was
restored. Further controlled light comparison precedes sensor limit changes.

### Ordinary-camera orientation follow-up (2026-09-07)

With installed FRONT/0 metadata, Snapcam saved
`IMG_20260907_234207.jpg` (271597 bytes, 1080x1920). Full ffmpeg decode passes;
visual inspection shows upright content matching the preview vertically and
the expected horizontal reversal between mirrored preview and unmirrored JPEG.
Private local copies: `.work/snapcam-front0-capture.jpg` and
`.work/camera-preview-current.png`. Darkness remains visible in both.

Added `mirror-snapcam-video-rotation.patch`: only on the Mirror, with unknown
orientation-sensor value, derive recorder orientation from display and camera
metadata, undoing mirror compensation for front cameras. Normal sensor-driven
behavior is unchanged. Builder applies it idempotently. Initial malformed patch
hunk failed before compilation; corrected counts, rebuilt successfully in 4:03.
APK `f3c60dc945dae894edefcb6e3eb3d5a5b4b96fc85316018ab0bcf8a5af412052`
installed successfully. Video saved-file validation is pending.

Validation subsequently passed: launched with the correct action
`android.media.action.VIDEO_CAMERA`, selected HD720p in the ordinary app's
settings, and enabled the existing nonpersistent `debug.mirror.video_raw=1`
compatibility switch. Portrait video preview has correct proportions. Log
reports `Mirror video rotation=270 (no orientation sensor)`.
`VID_20260907_234917.mp4` is 47,833,666 bytes, H264 1280x720, 795 frames over
38.692578s (~20.54fps), with 1842 AAC frames over 39.296s. Full ffmpeg decode
passes. Display matrix is reported as rotation90 by ffprobe (opposite sign
convention to Android's hint); default-decoded frame is visibly upright at
720x1280, matching the unmirrored JPEG. Private file and frame are under `.work/`.

Reflection: this verifies ordinary-app recording and orientation, not acceptable
brightness or A/V synchronization. High default bitrate and software encoding
still limit frame rate; prior 4Mbps probe tests were faster. Recording still
depends on a volatile debug property and needs a deliberate persistent setup.
Camera was sent Home after recording; do not reopen the clock. No system flash
was needed for this app update.

### Persistent recording setup and bitrate pass (2026-09-07)

Added Mirror-only ordinary 720p H264 cap at 4Mbps; high-speed, time-lapse and
other resolutions are untouched. This matches the earlier faster diagnostic
settings without reducing resolution. APK build passed in 4:01, SHA
`ba9c9c7a8da7122479ca30ca177ad0f49307796a78a8ed4dab4ba497429142da`, installed.
Added validated MIRROR_VIDEO_RAW=0/1 builder option (default1), installed through
build.prop as `debug.mirror.video_raw`; still shell-overridable for experiments.
The filesystem verifier now checks raw-buffer/packing library markers whenever
this mode is enabled, not only when rebuilding stagefright.

Buffer-packing tests rerun under address/undefined-behavior sanitizers passed
720p,1080p,VGA and non-aligned642x482 sizes. System image
`d4f5b63c05ce814a1049a3a3858b9c1a3eb0e12bba7f8178e7ae339014af308a`
passed build/filesystem inspection and system-only flash in76.321s.
Post-reboot recording/performance validation follows; do not infer success
from build/flash alone. No boot, firmware or userdata partition was changed.

Post-reboot validation: Android bootcomplete1 and video_raw1 without any shell
property setter. App logs4,000,000bps and orientation270. Saved
`VID_20260908_000505.mp4` is7,961,433bytes,413 H264frames/18.1235s (~22.79fps),
877AACframes/18.709333s. Full ffmpeg decode passes; inspected frame is upright.
Private copies `.work/snapcam-4m-first.mp4` and `.work/snapcam-4m-first.png`.
Ordinary app recording after reboot is verified; performance remains below30fps
and lower than the best diagnostic clips. No perceptual sync claim.

Diagnostic correction: initial all-black screenshots coincided with display
dozing; a later UI-visible black screenshot was captured during startup, before
the preview configuration log. Calling that a verified camera startup failure
was premature; the subsequent clip contains valid images. Known earlier
intermittent failures remain unresolved, but this attempt does not prove one.
Temporarily changed screen_off_timeout from1800000 to600000 during diagnosis,
then restored1800000. Camera closed/clients empty after Home. No clock restored.

Reflection: lower bitrate and persistent initialization improve everyday video
use, but do not address low-light image quality or guarantee startup reliability.
The room-light comparison remains pending. Future startup testing should wait
for configured preview and distinguish screen sleep from missing camera frames.

### Repeat-open validation and wake-sequence correction (2026-09-08)

Added bounded `mirror-test-camera-startup.mjs [1..10]`: verifies idle before
starting, removes only stale diagnostic report, wakes/dismisses keyguard,
launches the installed probe, waits up to25s for reported frame300, then Home
and verifies release/idle before another open. It preserves private reports
and power state under `.work/camera-startup-*`. It makes no firmware changes.
Frame-count success is explicitly not an image-quality assertion.

Initial warm run:3/3 reached300frames, first frame986/794/772ms, all clean
releases (`.work/camera-startup-1788826140497`). Rebooted Android. First runner
version only sent WAKEUP, without dismiss-keyguard: app reported only "Camera
probe ready", no Camera.open evidence or active client; Android dozed after10s.
It incorrectly reported a release timeout although the camera never opened.
Corrected wake sequence and no-open cleanup classification, retaining failure
exit when fewer than300frames arrive. This is not a sensor failure observation.

Corrected post-reboot run3/3 passed, first frames796/757/758ms, all clean
releases (`.work/camera-startup-1788826394361`). Frame300 mean Y16.83/16.63/14.78;
the last run's first frame was darker but settled by frame60. Six valid opens
increase confidence, not proof that historical intermittent failures are solved.
No hardware power-cycle performed, no settings/firmware changed this pass.
Brightness remains poor and the controlled lighting comparison is pending.

## Documentation checkpoint and phone comparison

The user subsequently supplied a phone photograph from the camera's angle,
showing a lit room and the ceiling light on. The contemporary Mirror image is
substantially darker/noisier. Phone processing makes this an uncalibrated
comparison; it nevertheless supersedes the assumption that the room was simply
unlit. No physical shutter or lens obstruction has been confirmed.

An exposure-control source audit found the reference command-18 forwarding path,
but verification of the installed binary's path was not completed. Experiments
were paused at the user's request to review, document and merge the repository.
The camera service was checked idle with one FRONT/0 device. No new camera test,
firmware write or automatic clock restoration was performed for this docs pass.
The current consolidated account is [camera/README.md](camera/README.md).

Documentation checkpoint validation: local Markdown targets passed; camera
builder shell syntax and both Node script syntax checks passed; NV12 packing
tests passed under address/undefined-behavior sanitizers for all four sizes and
invalid inputs. The diagnostic APK rebuilt successfully (legacy Camera API
deprecation warning only). Local system and Snapcam hashes matched the recorded
checkpoint. Staged files contain source/docs only; private captures, binaries
and unrelated personal notes were excluded. Full Android/Snapcam system builds
and live camera tests were not repeated during this documentation review.

## Resumed exposure-path audit: installed binary corroboration

After the merged documentation checkpoint, read-only analysis resumed. The
running sensor module was streamed through SHA-256 and matches the local HY22
input exactly: `2dfe67d7997c3caf462217be90f29258f59f1d90a81fe8a16e77228fba046f8b`.
Thumb disassembly identifies the exposure handler's command-18 construction at
`0x119fa`, ioctl request literal `0xc09056c1` at `0x11ae0`, and its call through
the wrapper at `0xde74`; that wrapper calls `ioctl@plt` at `0xde86`. The nearby
PC-relative logging string resolves to `sensor_set_exposure_compensation`.
This corroborates the reference implementation in the exact installed binary,
but does not yet prove runtime dispatch or a successful kernel register update.

The preceding +2 EV run's retained log shows the app accepted steps12 and
reported compensation12, preview90, 405 frames at15s and clean release3437ms;
frame300 mean luma was16.7913. No MirrorSensorABI entries remain in the current
ring buffer. Bounded tracing and ring retention mean their absence is not proof
that no command was issued. Do not infer that the control is missing merely
from missing logs. Next evidence needed: fresh runtime command/return tracing
and stock command-18 dispatch behavior. No firmware or sensor registers were
changed during this static audit.

## Live exposure sweep: startup-only parameter loss is insufficient explanation

Added an opt-in `exposureSweep` diagnostic: during one preview it requests
steps12 at5s, steps-12 at12s, then0 at19s. Changes use advertised Camera API
bounds, not direct sensor writes. The first attempt produced one near-empty
frame at8518ms (mean0.000752) and was excluded from exposure conclusions;
release completed2665ms. This re-observes the intermittent startup defect.

After confirmed release/idle, a fresh attempt delivered first frame847ms and
continuous preview. Baseline frame60 mean16.7184; live+12 accepted at frame119;
frame300 mean16.8413. Live-12 was accepted at314 and zero restored at517;
frame600 mean16.8168. There was no sampled frame inside the negative-EV interval,
so do not claim a measured negative-EV result. Live+2EV did not meaningfully
brighten this valid stream: startup-only parameter loss cannot fully explain
the ineffective control. The final source adds a60-frame minimum before sweep
changes, to avoid applying them during a failed startup; that guard has not yet
been rebuilt/deployed. The preceding sweep APK did build and install successfully.

Shell sensor-debug property writes still read back1, and `adb root` is refused.
No new sensor-handler log entries were available. No firmware changes or direct
register writes were made. Home ends the test and the clock is not restored.

## Exposure sweep with simultaneous sensor readback

Rebuilt/deployed the sweep guard and added luma reporting every60 frames during
the opt-in sweep. One valid continuous preview started at797ms. At4/9/16/23s,
the guarded exposure interface returned sensor5640, CCI enabled with one
reference, and identical values for all20 sampled registers. This covers
baseline/+2EV/-2EV/restored-zero intervals. In particular integration remained
`00/45/c0`, gain`02/00`, gain ceiling`02/00`, targets`30/28/30/26`, and
brightness`00/01`. API readback accepted12, -12 and0 at frames115/289/468.

Baseline frame60 luma16.8496; +2EV frame18016.6832 and frame24016.8453;
-2EV frame36016.5528 and frame42016.8455; restored-zero frame54016.7233.
Thus neither sign of compensation produced a meaningful measured response in
this lit scene, including the sensor's sampled exposure settings. This is
stronger than the earlier startup-only test, but does not identify the exact
layer dropping/ignoring the command or prove that every sensor register is
unchanged. Investigate dispatch/driver support before implementing a software
brightness workaround. Private reports:
`.work/exposure-register-sweep-1788828395327`. Clean release357ms; no firmware
or sensor-register writes were performed. The changes were standard camera API
requests and bounded sensor reads; zero was restored before closing.

## Stock exposure handler is a successful no-op

A guarded dispatch decoder now verifies ten exact AArch64 instructions at
config32+0x24, bounds its48-byte jump-table read to named kernel rodata and
validates all24 targets within the inspected function. It exposes command
numbers/relative offsets only: no arbitrary reads, execution or sensor writes.
Module build passed with stock symbol versions and no GOT relocations.
Module SHA256: `3c08c45d1a11749169b24481eec3fd30b56816cc6ce892716a120579663532ac`.
System SHA256: `93a1dee922fdd55be624a865bcca346a732d5ea59a28f44c42975dd3068cf92b`.
System-only flash77.386s, reboot completed1; table read succeeded with camera
closed. The previous d4f5 image is retained locally. Sensor/HAL/media/CPP/Wi-Fi
hashes remained unchanged in the generated filesystem.

Commands14 through24, including exposure compensation18, all dispatch to
config32+0x58c. Captured code there sets x19=0, unlocks the mutex and returns
w0=w19. It reads no control value and writes no sensor register. Thus exposure
compensation is an unimplemented control that returns success. Command25 and
normal mode/start/stop have distinct handlers. Runtime forwarding may still
need verification, but forwarding alone cannot fix a no-op handler.

Next: implement a narrowly scoped reversible exposure path with validated
register limits and normal AEC preserved. No exposure correction is installed
yet. This finding does not resolve intermittent startup or prove that exposure
compensation alone explains all of the darkness.

## Exposure implementation preparation

Cross-checked the six AEC target register roles against Linux's
[OV5640 driver](https://code.googlesource.com/linux/torvalds/linux/+/refs/heads/master/drivers/media/i2c/ov5640.c)
(`ov5640_set_ae_target`). Both captured stock mode tables contain the same
baseline: addresses3a0f/3a10/3a1b/3a1e/3a11/3a1f map to30/28/30/26/60/14 hex.
Added a pure, not-yet-connected register-plan helper: Android's -12..12 steps
scale those baselines at1/6EV, clamp to byte range, and exactly restore stock at0.
No gain-ceiling, integration-time, frame-length, clock or AEC-enable writes are
part of that plan. This is a proposed mapping, not a claim of calibrated sensor
EV response. Existing gain/exposure saturation may limit positive response.

Host tests passed with address/undefined-behavior sanitizers: invalid bounds,
monotonic output, ordered target windows, byte saturation and exact zero-EV
restoration. The helper has not been connected to ioctl forwarding or deployed.
The observed sensor node is v4l-subdev6, but future forwarding must verify its
sysfs name is ov5640 rather than assuming that enumeration is permanent.

## Exposure bridge built, not yet enabled on device

Connected the target-plan helper to the32-bit compatibility ioctl hook. It
requires explicit `debug.mirror.exposure_bridge=1`, exact request0xc09056c1,
command18, a file descriptor resolving to a numeric v4l-subdev path and sysfs
name `ov5640`. Other requests retain their original path. Accepted steps are
-12..12; null/out-of-range values fail. Six fixed target registers are sent
through existing command2 (CFG_WRITE_I2C_ARRAY), whose stock handler is present.
The24-byte setting and8-byte entries match stock config32 disassembly, with
compile-time size/offset checks. The real ioctl return/errno is propagated;
there is no claim of atomic multi-register writes or rollback on an I2C error.

The final bridge compiled with -Wall/-Wextra/-Werror; SHA256
`09e56650ffedc0b9e26ea31477b2f6d2a7385b068e1e1ff7a6301c05b7f777ca`.
Daemon hash is unchanged. Final-image builder now supports
`MIRROR_EXPOSURE_BRIDGE=1` (default0), validates0/1, and checks the enabled
property plus bridge marker in the image. Shell syntax/diff checks passed.
No new system image was built/flashed for this bridge yet; the installed93a1
diagnostic image remains current. Next test must confirm command interception,
kernel success and register readback before judging brightness. Positive gain
headroom remains separately limited by the observed configured ceiling.

## Exposure bridge live verification: register control works, darkness persists

Installed bridge-enabled system SHA256
`3777cfc1059cc8018bc22c17b889e5218c16a56b80e3354e74dfa25569eee33c`
with system-only flash76.423s. Boot completed1, exposure_bridge1; installed
compatibility-library hash matches09e56650…f777ca. The initial unauthorized
ADB state cleared after normal boot; no key or userdata changes were needed.

Valid continuous preview first frame883ms. Readback at4s showed stock targets;
at9s (+12) targets3a0f/10/1b/1e became c0/a0/c0/98; at16s (-12) they became
0c/0a/0c/0a; at23s (zero) they returned30/28/30/26. This confirms interception
and actual sensor register updates, despite no retained MirrorExposure log
entries. Only four of the six target registers are in the current diagnostic
read set; do not claim direct readback of the other two.

Luma remained roughly16.35–16.82, while integration00/45/c0 and gain02/00 stayed
fixed at all snapshots. AEC enabled, gain ceiling02/00 and frame length04/60
also remained unchanged. Thus the missing command is repaired at the register
level, but brightness is not fixed. Next investigate AEC's own measured average
and its gain/integration limits, alongside an external lens-cover check. Do not
claim that target changes alone can overcome saturation or optical attenuation.
Private evidence: `.work/exposure-bridge-1788829618837`. Zero restored and camera
released117ms. No automatic clock restoration.

## Gain headroom experiment prepared (not deployed)

The [OV5640 datasheet](https://cdn.sparkfun.com/datasheets/Sensors/LightImaging/OV5640_DS.pdf)
and [Linux gain-control correction](https://git.ti.com/cgit/ti-linux-kernel/ti-linux-kernel/commit/drivers/media/i2c/ov5640.c?h=ti-linux-6.1.y&id=ee56050deee888643f1d640caf3ea83d0034e009)
identify a10-bit gain ceiling in3a18/19. The observed0x200 leaves approximately
another factor of two before0x3ff. Increasing gain also amplifies noise; the
analogue/digital split is not assumed.

Added optional `debug.mirror.gain_headroom=1`: positive exposure requests append
ceiling0x3ff to the existing target writes; zero/negative requests restore the
observed stock0x200. Default remains disabled. This does not force manual gain,
change AEC enable, lengthen frames or change clocks. The final builder accepts
`MIRROR_GAIN_HEADROOM=1` only alongside the exposure bridge. Gain and target
changes together require comparison against the already measured target-only
test; no isolated gain response has been measured yet.

Expanded guarded readback from20 to23 registers with fast-target3a11/1f and
sensor average56a1. Both builds passed: compatibility library
`bf1dd1c8a68e77d161584ea14c863ccb4ae4fcc411264f22d862eb501d4934ef`,
diagnostic module
`f0e8000420cce72007b138109149c14ef8898e61ab1d31a516720f4c8b0afb65`.
Existing target-plan sanitizer tests and builder syntax passed. These components
have not yet been packed/flashed; installed3777cfc1… remains current. User's
non-invasive lens-cover check remains unanswered; no hardware obstruction is
assumed. Next live test must verify gain ceiling, actual gain, sensor average,
image quality and zero restoration before retaining any new default.

## Gain headroom deployed: measurable improvement, brightness still unresolved

Installed system SHA-256
`a6b0c96810b9b0ef2998a2ec2e83614fb77b4aa1170c3c0f13a1358e39d67a38`;
system-only flash completed in 77.996 seconds and Android boot was verified.
The bridge and gain-headroom properties are enabled. Compatibility and diagnostic
hashes match the preceding prepared components; sensor, HAL, media, CPP and Wi-Fi
components remain unchanged. The preceding “not deployed” entry is historical.

Private sweep evidence: `.work/gain-headroom-1788830187376`. Baseline preview
luma ~17.4 increased to 32.6–33.3 with +12 compensation. At the positive snapshot,
actual gain and ceiling both became `0x3ff` from `0x200`, and sensor average
`56a1` rose from `07` to `0d`. All six target registers were sampled: positive
`c0/a0/c0/98/ff/50`, negative `0c/0a/0c/0a/18/05`, restored zero
`30/28/30/26/60/14`. Negative and zero requests restored ceiling/actual gain
`0x200`; luma returned ~17.3–17.5. Integration `00/45/c0`, AEC `3503=00` and
frame length `04/60` remained unchanged. Camera release took 2313 ms; zero was
restored before closing and the clock was not reopened.

This is about 1.9× measured luma, not calibrated +2 EV / 4× brightness. It shows
the automatic gain path responds when given headroom. Visual inspection still
shows a dark, noisy room, so the brightness issue remains open. Current lighting
was not controlled against the user's older phone photo. No lens obstruction
is established. This test did not revalidate saved JPEG/video, perceptual A/V
sync, physical cold starts or fix intermittent blank starts. Current docs now
separate this installed experiment from the earlier baseline and rejected tests.
