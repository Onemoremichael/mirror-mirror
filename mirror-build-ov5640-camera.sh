#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
source_image="$repo_root/.work/mirror-android-build.ext4.img"
camera_source="$repo_root/.work/quectel-sc20-camera"
compat_patch="$repo_root/camera/quectel-ov5640-hy22-abi.patch"
modes_patch="$repo_root/camera/quectel-ov5640-hy22-modes.patch"
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"
camera_commit=ed0e50a102c7ee115c6999ba0a26ce50537c616e

if [[ ! -f "$source_image" ]]; then
  echo "Missing reconstructed Android build image: $source_image" >&2
  exit 1
fi

if [[ ! -d "$camera_source/.git" ]]; then
  git clone https://github.com/copslock/Quectel_sc20_linux_sdk.git "$camera_source"
fi
for required_patch in "$compat_patch" "$modes_patch"; do
  if [[ ! -f "$required_patch" ]]; then
    echo "Missing HY22 camera patch: $required_patch" >&2
    exit 1
  fi
done
git -C "$camera_source" checkout --detach "$camera_commit"
mkdir -p "$artifact_dir"

docker run --rm --platform linux/amd64 --privileged \
  -v "$source_image:/build.img:ro" \
  -v "$camera_source:/camera:ro" \
  -v "$compat_patch:/hy22-abi.patch:ro" \
  -v "$modes_patch:/hy22-modes.patch:ro" \
  -v "$artifact_dir:/artifacts" \
  alleen/apq8016_bm bash -lc '
set -e
mkdir -p /mnt/build
mount -o loop,ro /build.img /mnt/build
trap "umount /mnt/build" EXIT

cc=/mnt/build/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-gcc
strip=/mnt/build/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-strip
readelf=/mnt/build/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-readelf
sysroot=/mnt/build/prebuilts/ndk/9/platforms/android-21/arch-arm
sensors=/camera/camera/services/mm-camera-legacy/mm-camera2/media-controller/modules/sensors
flags="--sysroot=$sysroot -fPIC -shared -Wl,--no-undefined -I$sensors/includes -I/mnt/build/out/target/product/msm8916_64/obj/KERNEL_OBJ/usr/include -I/mnt/build/system/core/include"

$cc $flags -Wl,-soname,libmmcamera_ov5645-validation.so \
  -o /tmp/libmmcamera_ov5645-validation.so \
  "$sensors/sensor_libs/ov5645/ov5645_lib.c"

symbol_line=$($readelf -s /tmp/libmmcamera_ov5645-validation.so \
  | grep "sensor_lib_ptr$" | head -1)
set -- $symbol_line
abi_size=$3
if [[ "$abi_size" != 380 ]]; then
  echo "Unexpected Qualcomm sensor_lib_t size: $abi_size (expected 380)" >&2
  exit 1
fi

# The HY22 prebuilt sensor module reads sensor_stream_info_array at byte 68 and
# advances through sensor_lib_out_info_t in 32-byte records. This later Quectel
# header puts the pointer at byte 72 and uses 36-byte records because it added
# parse_RDI_stats and is_pdaf_supported. OV5640 uses neither addition, so build
# this one library against a private header matching the module on the Mirror.
mkdir -p /tmp/hy22-include
cp "$sensors/includes/sensor_lib.h" /tmp/hy22-include/sensor_lib.h
patch /tmp/hy22-include/sensor_lib.h < /hy22-abi.patch
cp "$sensors/sensor_libs/ov5640/ov5640_lib.c" /tmp/ov5640_lib.c
patch /tmp/ov5640_lib.c < /hy22-modes.patch
# msm8916 uses the Qualcomm VFE 4.0 camera pipeline. The normal Android make
# hierarchy supplies this define from media-controller/Android.mk; retain it in
# the standalone build so the OV5640 configures a normal two-lane CSI PHY
# rather than the older combo-mode layout.
hy22_flags="--sysroot=$sysroot -fPIC -shared -Wl,--no-undefined -DVFE_40 -I/tmp/hy22-include -I$sensors/includes -I/mnt/build/out/target/product/msm8916_64/obj/KERNEL_OBJ/usr/include -I/mnt/build/system/core/include"

$cc $hy22_flags -Wl,-soname,libmmcamera_ov5640.so \
  -o /artifacts/libmmcamera_ov5640.so \
  /tmp/ov5640_lib.c
$readelf -Ws /artifacts/libmmcamera_ov5640.so | grep -q ov5640_open_lib
sensor_line=$($readelf -s /artifacts/libmmcamera_ov5640.so \
  | grep "sensor_lib_ptr$" | head -1)
set -- $sensor_line
sensor_size=$3
if [[ "$sensor_size" != 376 ]]; then
  echo "Unexpected HY22-compatible sensor_lib_t size: $sensor_size (expected 376)" >&2
  exit 1
fi
out_info_line=$($readelf -s /artifacts/libmmcamera_ov5640.so \
  | grep "sensor_out_info$" | head -1)
set -- $out_info_line
out_info_size=$3
if [[ "$out_info_size" != 96 ]]; then
  echo "Unexpected HY22 output-info array size: $out_info_size (expected 96)" >&2
  exit 1
fi
$strip --strip-unneeded /artifacts/libmmcamera_ov5640.so
'

shasum -a 256 "$artifact_dir/libmmcamera_ov5640.so"
