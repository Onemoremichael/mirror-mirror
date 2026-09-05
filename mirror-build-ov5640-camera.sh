#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
source_image="$repo_root/.work/mirror-android-build.ext4.img"
camera_source="$repo_root/.work/quectel-sc20-camera"
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"
camera_commit=ed0e50a102c7ee115c6999ba0a26ce50537c616e

if [[ ! -f "$source_image" ]]; then
  echo "Missing reconstructed Android build image: $source_image" >&2
  exit 1
fi

if [[ ! -d "$camera_source/.git" ]]; then
  git clone https://github.com/copslock/Quectel_sc20_linux_sdk.git "$camera_source"
fi
git -C "$camera_source" checkout --detach "$camera_commit"
mkdir -p "$artifact_dir"

docker run --rm --platform linux/amd64 --privileged \
  -v "$source_image:/build.img:ro" \
  -v "$camera_source:/camera:ro" \
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

$cc $flags -Wl,-soname,libmmcamera_ov5640.so \
  -o /artifacts/libmmcamera_ov5640.so \
  "$sensors/sensor_libs/ov5640/ov5640_lib.c"
$readelf -Ws /artifacts/libmmcamera_ov5640.so | grep -q ov5640_open_lib
$strip --strip-unneeded /artifacts/libmmcamera_ov5640.so
'

shasum -a 256 "$artifact_dir/libmmcamera_ov5640.so"
