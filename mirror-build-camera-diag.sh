#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
source_image="$repo_root/.work/mirror-android-build.ext4.img"
module_source="$repo_root/camera"
running_config="$repo_root/artifacts/android-m-msm8916_64/running-kernel-build.config"
running_symvers="$repo_root/artifacts/android-m-msm8916_64/Module-stock-kernel.symvers"
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"

for required in "$source_image" "$module_source/Makefile" \
  "$module_source/mirror_camera_diag.c" "$running_config" "$running_symvers"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing camera diagnostic build input: $required" >&2
    exit 1
  fi
done
mkdir -p "$artifact_dir"

docker run --rm --platform linux/amd64 --privileged \
  -v "$source_image:/build.img" \
  -v "$module_source:/module:ro" \
  -v "$running_config:/running-kernel.config:ro" \
  -v "$running_symvers:/running-kernel.symvers:ro" \
  -v "$artifact_dir:/artifacts" \
  alleen/apq8016_bm bash -lc '
set -e
mkdir -p /mnt/build
mount -o loop /build.img /mnt/build
trap "umount /mnt/build" EXIT

kernel=/mnt/build/kernel
kernel_out=/mnt/build/out/kernel-running-mirror
cross=/mnt/build/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-

mkdir -p "$kernel_out"
cp /running-kernel.config "$kernel_out/.config"
make -C "$kernel" O="$kernel_out" ARCH=arm64 CROSS_COMPILE="$cross" \
  olddefconfig prepare modules_prepare
cp /running-kernel.symvers "$kernel_out/Module.symvers"
rm -rf /tmp/mirror-camera-module
mkdir -p /tmp/mirror-camera-module
cp /module/Makefile /module/mirror_camera_diag.c /tmp/mirror-camera-module/
make -C "$kernel" O="$kernel_out" ARCH=arm64 CROSS_COMPILE="$cross" \
  M=/tmp/mirror-camera-module modules
if "${cross}readelf" -r /tmp/mirror-camera-module/mirror_camera_diag.ko | grep -q "R_AARCH64_.*GOT"; then
  echo "Stock kernel cannot load GOT relocations in this module" >&2
  exit 1
fi
cp /tmp/mirror-camera-module/mirror_camera_diag.ko \
  /artifacts/mirror_camera_diag.ko
modinfo /artifacts/mirror_camera_diag.ko
'

shasum -a 256 "$artifact_dir/mirror_camera_diag.ko"
