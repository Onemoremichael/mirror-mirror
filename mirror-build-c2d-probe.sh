#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")" && pwd)
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"
source_lib="$repo_root/.work/android-m/vendor/qcom/proprietary/prebuilt_HY22/target/product/msm8916_64/system/vendor/lib/libmmcamera2_c2d_module.so"
expected=1849b9ef4d7161ce52f6c29da8f7721876f54c6241ceb637a6c497dd31986932
[[ $(shasum -a 256 "$source_lib" | awk '{print $1}') == "$expected" ]]
docker run --rm --platform linux/amd64 --privileged \
  -v "$repo_root/.work/mirror-android-build.ext4.img:/build.img:ro" \
  -v "$repo_root/camera/c2d-probe.c:/probe.c:ro" \
  -v "$repo_root/camera/c2d-loader-check.c:/check.c:ro" \
  -v "$artifact_dir:/artifacts" alleen/apq8016_bm bash -lc '
set -e
mkdir -p /mnt/build
mount -o loop,ro /build.img /mnt/build
trap "umount /mnt/build" EXIT
cc=/mnt/build/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-gcc
sysroot=/mnt/build/prebuilts/ndk/9/platforms/android-21/arch-arm
"$cc" --sysroot="$sysroot" -march=armv7-a -fPIC -shared -nostdlib -Wall -Wextra -Werror \
 -I/mnt/build/hardware/qcom/display/libcopybit -Wl,-soname,libMD2.so \
 -o /artifacts/libMD2.so /probe.c
"$cc" --sysroot="$sysroot" -march=armv7-a -fPIE -pie -nostdlib \
 "$sysroot/usr/lib/crtbegin_dynamic.o" /check.c -lc -ldl \
 "$sysroot/usr/lib/crtend_android.o" -o /artifacts/c2d-loader-check
'
# Other dlsym requests on this wrapper resolve through the original library.
patchelf --add-needed libC2D2.so "$artifact_dir/libMD2.so"
node - "$source_lib" "$artifact_dir/libmmcamera2_c2d_module-probe.so" <<'JS'
const fs = require('fs');
const b = fs.readFileSync(process.argv[2]);
const from = Buffer.from('libC2D2.so\0'), to = Buffer.from('libMD2.so\0\0');
const offset = b.indexOf(from);
if (offset < 0 || b.indexOf(from, offset + 1) !== -1 || from.length !== to.length)
  throw Error('Unexpected C2D loader string layout');
to.copy(b, offset);
fs.writeFileSync(process.argv[3], b);
JS
shasum -a 256 "$artifact_dir/libMD2.so" "$artifact_dir/libmmcamera2_c2d_module-probe.so"
