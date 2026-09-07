#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
source_image="$repo_root/.work/mirror-android-build.ext4.img"
daemon_source="$repo_root/.work/android-m/vendor/qcom/proprietary/prebuilt_HY22/target/product/msm8916_64/system/bin/mm-qcamera-daemon"
compat_source="$repo_root/camera/legacy-camera-compat.c"
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"
compat_library="$artifact_dir/libmmcamera_mirror_haf.so"
patched_daemon="$artifact_dir/mm-qcamera-daemon-mirror"
readelf_tool="$repo_root/.work/android-m/prebuilts/gcc/darwin-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-readelf"

for required in "$source_image" "$daemon_source" "$compat_source" "$readelf_tool"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing camera compatibility input: $required" >&2
    exit 1
  fi
done
if ! command -v patchelf >/dev/null 2>&1; then
  echo "patchelf is required (macOS: brew install patchelf)" >&2
  exit 1
fi
mkdir -p "$artifact_dir"

docker run --rm --platform linux/amd64 --privileged \
  -v "$source_image:/build.img:ro" \
  -v "$compat_source:/legacy-camera-compat.c:ro" \
  -v "$artifact_dir:/artifacts" \
  alleen/apq8016_bm bash -lc '
set -e
mkdir -p /mnt/build
mount -o loop,ro /build.img /mnt/build
trap "umount /mnt/build" EXIT
cc=/mnt/build/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-gcc
sysroot=/mnt/build/prebuilts/ndk/9/platforms/android-21/arch-arm
"$cc" --sysroot="$sysroot" -fPIC -shared -nostdlib \
  -Wall -Wextra -Werror \
  -Wl,-soname,libmmcamera_mirror_haf.so \
  -o /artifacts/libmmcamera_mirror_haf.so /legacy-camera-compat.c
'

cp "$daemon_source" "$patched_daemon"
chmod 0755 "$patched_daemon"
patchelf --add-needed libmmcamera_mirror_haf.so "$patched_daemon"
patchelf --print-needed "$patched_daemon" | grep -qx libmmcamera_mirror_haf.so
"$readelf_tool" -Ws "$compat_library" | grep -Eq '[[:space:]]ioctl$'
shasum -a 256 "$compat_library" "$patched_daemon"
