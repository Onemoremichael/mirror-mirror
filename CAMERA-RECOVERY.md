# OV5640 camera recovery notes

## Current result

Android detects one camera, opens it, reads its parameters, and configures the
OV5640 without crashing the Qualcomm camera daemon. Preview still produces no
frames because the legacy ISP does not select the sensor's YUYV stream as its
primary format.

This distinction matters: sensor detection, the userspace ABI, the supported
resolution table, and CSI lane routing are now working. The remaining work is
inside the preserved Qualcomm ISP/stream pipeline.

## Reproducible library

`mirror-build-ov5640-camera.sh` pins the camera source tree to commit
`ed0e50a102c7ee115c6999ba0a26ce50537c616e`, validates the source ABI, applies
the two narrow patches, builds a 32-bit sensor library, and validates its
resulting structure sizes before stripping it.

```sh
./mirror-build-ov5640-camera.sh
./mirror-build-camera-compat.sh
./mirror-build-final-system.sh
```

The resulting library installed on the tested unit is:

```text
libmmcamera_ov5640.so
SHA-256 c268c69d8efa15f603f936c9a5aa987ad4d551bd9eef6472152a8dc4b49d951f
```

`camera/quectel-ov5640-hy22-abi.patch` removes two later additions that the
HY22 prebuilt sensor module does not expect. The build verifies a 376-byte
`sensor_lib_t` and a 96-byte, three-record output-info array.

`camera/quectel-ov5640-hy22-modes.patch` removes the unsupported fourth VGA
entry and sets the physical route observed on this board:

```text
lane count: 2
lane assignment: 0x4320
lane mask: 0x7
CSID core: 1
CSI PHY: 1
settle count: 0x1b
```

The three remaining sensor modes are 2592×1944, 1280×960, and 1920×1080. The
legacy camera service reports the corresponding packed YUV widths as 5184,
2560, and 3840.

## Verified log progression

After the ABI correction, the earlier `port_sensor_create` segmentation fault
is gone. A 640×480 client request selects kernel resolution 1, which the driver
accepts as `ov5640_sxga_settings`. The camera service then reports the explicit
two-lane CSIPHY and CSID configuration shown above.

The remaining signature is:

```text
isp_hw_find_primary_cid: error cannot find primary sensor format
```

No preview frames arrive and the stream-on chain through ISP, CPP, and C2D does
not complete. The latest local diagnostic log is
`.work/camera-phy1-logcat.txt`; `.work` and captured images are intentionally
excluded from Git.

## Safe next investigation

A future camera pass should stay at the sensor/ISP userspace boundary. The most
targeted next comparison is the virtual-channel description presented to the
ISP—especially whether this HY22 binary expects only the YUYV image CID rather
than the separate embedded-data CID. No bootloader, boot, recovery, modem,
trust, partition-table, or board firmware change is required for that work.
