# OV5640 camera recovery notes — 2026-09-06

## Current result

There is one physical front camera. Android enumerates one camera; the
replacement sensor library labels it BACK. That label does not indicate a
second physical camera.

Sensor discovery and parameter reads work. Preview still produces no frames.
The latest route-0 tests produce substantial CSIPHY interrupt activity, very
little CSID progress and a start-of-frame timeout. This does not yet establish
the exact remaining hardware or driver configuration issue.

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

## Prepared diagnostic module — not deployed

`mirror_camera_diag.c` exposes selected CSIPHY0/CSID0 registers and camera
device-tree properties at `/proc/mirror_camera_diag`. It performs no explicit
register writes. It is hardware-specific diagnostic code, not a camera fix;
live reads still require care about the receiver's powered state.

The module and a system image containing it were built before hardware work
was paused. **That image has not been flashed**, and the proc entry is absent
from the running system.

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

## Next camera session

Capture receiver state during the first seconds of a stream attempt, before
the timeout resets it. Compare lane state, routing and packet counters before
choosing another change. Keep the camera work separate from Afterglow: the
clock app does not access the camera or require new firmware.

The TimStewartJ repository provides an application-level camera consumer and
retry behavior, but the reviewed implementation did not supply a replacement
HAL/kernel fix for this receiver issue.
