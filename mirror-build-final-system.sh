#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
build_image="$repo_root/.work/mirror-android-build.ext4.img"
wifi_source="$repo_root/.work/android-m/frameworks/opt/net/wifi/service/java/com/android/server/wifi/WifiStateMachine.java"
product_properties="$repo_root/.work/android-m/device/qcom/msm8916_64/system.prop"
camera_library="$repo_root/artifacts/android-m-msm8916_64/libmmcamera_ov5640.so"
camera_compat_library="$repo_root/artifacts/android-m-msm8916_64/libmmcamera_mirror_haf.so"
camera_daemon="$repo_root/artifacts/android-m-msm8916_64/mm-qcamera-daemon-mirror"
camera_cpp_library="$repo_root/artifacts/android-m-msm8916_64/libmmcamera2_cpp_module-mirror.so"
camera_diag_module="$repo_root/artifacts/android-m-msm8916_64/mirror_camera_diag.ko"
camera_module_source="$repo_root/.work/android-m/vendor/qcom/proprietary/prebuilt_HY22/target/product/msm8916_64/system/vendor/lib"
wlan_module="$repo_root/artifacts/android-m-msm8916_64/pronto_wlan-stock-kernel.ko"
post_boot_source="$repo_root/.work/android-m/device/qcom/common/rootdir/etc/init.qcom.post_boot.sh"
artifact_dir="$repo_root/artifacts/android-m-msm8916_64"
output_image="$artifact_dir/system-mirror-final.img"
build_log="$artifact_dir/mirror-final-system-build.log"

for required in "$build_image" "$wifi_source" "$product_properties" "$camera_library" "$camera_compat_library" "$camera_daemon" "$camera_cpp_library" "$camera_diag_module" "$wlan_module" "$post_boot_source"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing required build input: $required" >&2
    exit 1
  fi
done
if [[ ! -d "$camera_module_source" ]]; then
  echo "Missing camera module directory: $camera_module_source" >&2
  exit 1
fi
mkdir -p "$artifact_dir"

docker run --rm --platform linux/amd64 --privileged \
  -e MIRROR_REPACK_ONLY="${MIRROR_REPACK_ONLY:-0}" \
  -v "$build_image:/build.img" \
  -v "$wifi_source:/inputs/WifiStateMachine.java:ro" \
  -v "$product_properties:/inputs/system.prop:ro" \
  -v "$camera_library:/inputs/libmmcamera_ov5640.so:ro" \
  -v "$camera_compat_library:/inputs/libmmcamera_mirror_haf.so:ro" \
  -v "$camera_daemon:/inputs/mm-qcamera-daemon:ro" \
  -v "$camera_cpp_library:/inputs/libmmcamera2_cpp_module.so:ro" \
  -v "$camera_diag_module:/inputs/mirror_camera_diag.ko:ro" \
  -v "$camera_module_source:/camera-modules:ro" \
  -v "$wlan_module:/inputs/pronto_wlan-stock-kernel.ko:ro" \
  -v "$post_boot_source:/inputs/init.qcom.post_boot.sh:ro" \
  -v "$artifact_dir:/artifacts" \
  alleen/apq8016_bm bash -lc '
set -e
mkdir -p /mnt/build
mount -o loop /build.img /mnt/build
cleanup() {
  sync
  cd /
  umount /mnt/build 2>/dev/null || umount -l /mnt/build 2>/dev/null || true
}
trap cleanup EXIT

cmp -s /inputs/WifiStateMachine.java \
  /mnt/build/frameworks/opt/net/wifi/service/java/com/android/server/wifi/WifiStateMachine.java \
  || cp /inputs/WifiStateMachine.java \
    /mnt/build/frameworks/opt/net/wifi/service/java/com/android/server/wifi/WifiStateMachine.java
cmp -s /inputs/system.prop /mnt/build/device/qcom/msm8916_64/system.prop \
  || cp /inputs/system.prop /mnt/build/device/qcom/msm8916_64/system.prop
cmp -s /inputs/init.qcom.post_boot.sh \
  /mnt/build/device/qcom/common/rootdir/etc/init.qcom.post_boot.sh \
  || cp /inputs/init.qcom.post_boot.sh \
    /mnt/build/device/qcom/common/rootdir/etc/init.qcom.post_boot.sh
cd /mnt/build
export USE_CCACHE=1
export CCACHE_DIR=/mnt/build/.ccache
source build/envsetup.sh >/dev/null
lunch msm8916_64-userdebug >/dev/null

# Rebuild the modified framework service and regenerate the product image so
# the product property is folded into build.prop. MIRROR_REPACK_ONLY=1 is for
# layering changed boot-time files onto an already successful full build.
if [ "$MIRROR_REPACK_ONLY" != 1 ]; then
  make -j4 wifi-service systemimage 2>&1 | tee /artifacts/mirror-final-system-build.log
fi

# The legacy camera module comes from a separately pinned, ABI-checked build.
# Install it into the staged vendor library directory, then repack that exact
# staging tree rather than making it an untracked platform build dependency.
install -m 0755 /inputs/libmmcamera_ov5640.so \
  out/target/product/msm8916_64/system/vendor/lib/libmmcamera_ov5640.so
install -m 0755 /inputs/libmmcamera_mirror_haf.so \
  out/target/product/msm8916_64/system/vendor/lib/libmmcamera_mirror_haf.so
install -m 0755 /inputs/mm-qcamera-daemon \
  out/target/product/msm8916_64/system/bin/mm-qcamera-daemon

# The Qualcomm userdebug product recipe leaves the camera media-controller
# modules in MM_CAMERA_DBG instead of the default product package list. The
# daemon is still installed and links all six at startup, so omitting them
# makes the legacy linker abort before sensor discovery. Restore the matching
# 32-bit prebuilts from this exact platform source tree.
camera_prebuilts=/camera-modules
for camera_module in \
  libmmcamera2_stats_modules.so \
  libmmcamera2_iface_modules.so \
  libmmcamera2_isp_modules.so \
  libmmcamera2_sensor_modules.so \
  libmmcamera2_pproc_modules.so \
  libmmcamera2_imglib_modules.so \
  libmmcamera2_c2d_module.so \
  libmmcamera2_cpp_module.so \
  libmmcamera2_vpe_module.so \
  libmmcamera2_wnr_module.so; do
  install -m 0755 "$camera_prebuilts/$camera_module" \
    "out/target/product/msm8916_64/system/vendor/lib/$camera_module"
done
# This YUV sensor performs AEC/AWB internally and has no separate Qualcomm
# statistics producer. Use the narrowly patched CPP module that treats its
# missing initial AEC update as non-fatal while retaining the normal path.
install -m 0755 /inputs/libmmcamera2_cpp_module.so \
  out/target/product/msm8916_64/system/vendor/lib/libmmcamera2_cpp_module.so
install -m 0644 /inputs/pronto_wlan-stock-kernel.ko \
  out/target/product/msm8916_64/system/lib/modules/pronto/pronto_wlan.ko
install -m 0644 /inputs/mirror_camera_diag.ko \
  out/target/product/msm8916_64/system/lib/modules/mirror_camera_diag.ko
install -m 0755 /inputs/init.qcom.post_boot.sh \
  out/target/product/msm8916_64/system/etc/init.qcom.post_boot.sh
post_boot=out/target/product/msm8916_64/system/etc/init.qcom.post_boot.sh
if ! grep -q "mirror_camera_diag" "$post_boot"; then
  cat >> "$post_boot" <<"POST_BOOT_EOF"

# Mirror revival: expose read-only CSI diagnostics for camera bring-up.
if [ -f /system/lib/modules/mirror_camera_diag.ko ]; then
    insmod /system/lib/modules/mirror_camera_diag.ko
fi
POST_BOOT_EOF
fi
make -j4 snod 2>&1 | tee -a /artifacts/mirror-final-system-build.log

cp out/target/product/msm8916_64/system.img /artifacts/system-mirror-final.img

# Inspect the generated filesystem itself before it leaves the build container.
raw=/tmp/mirror-final-system.raw.img
inspect=/tmp/mirror-final-system
out/host/linux-x86/bin/simg2img /artifacts/system-mirror-final.img "$raw"
mkdir -p "$inspect"
mount -o loop,ro "$raw" "$inspect"
grep -qx "service.adb.tcp.port=5555" "$inspect/build.prop"
test -s "$inspect/framework/wifi-service.jar"
test -s "$inspect/vendor/lib/libmmcamera_ov5640.so"
test -s "$inspect/vendor/lib/libmmcamera_mirror_haf.so"
test -s "$inspect/bin/mm-qcamera-daemon"
for camera_module in \
  libmmcamera2_stats_modules.so \
  libmmcamera2_iface_modules.so \
  libmmcamera2_isp_modules.so \
  libmmcamera2_sensor_modules.so \
  libmmcamera2_pproc_modules.so \
  libmmcamera2_imglib_modules.so \
  libmmcamera2_c2d_module.so \
  libmmcamera2_cpp_module.so \
  libmmcamera2_vpe_module.so \
  libmmcamera2_wnr_module.so; do
  test -s "$inspect/vendor/lib/$camera_module"
done
test -s "$inspect/lib/modules/pronto/pronto_wlan.ko"
test -s "$inspect/lib/modules/mirror_camera_diag.ko"
sha256sum "$inspect/vendor/lib/libmmcamera_ov5640.so" /inputs/libmmcamera_ov5640.so
sha256sum "$inspect/vendor/lib/libmmcamera2_cpp_module.so" /inputs/libmmcamera2_cpp_module.so
sha256sum "$inspect/lib/modules/pronto/pronto_wlan.ko" /inputs/pronto_wlan-stock-kernel.ko
umount "$inspect"
'

shasum -a 256 "$output_image" "$camera_library"
echo "Final system image: $output_image"
echo "Build log: $build_log"
