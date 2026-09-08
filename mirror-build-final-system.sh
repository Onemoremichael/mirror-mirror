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
  -e MIRROR_CAMERA_VERBOSE="${MIRROR_CAMERA_VERBOSE:-0}" \
  -e MIRROR_C2D_PROBE="${MIRROR_C2D_PROBE:-0}" \
  -e MIRROR_FIRMWARE_AUDIT="${MIRROR_FIRMWARE_AUDIT:-0}" \
  -e MIRROR_REBUILD_STAGEFRIGHT="${MIRROR_REBUILD_STAGEFRIGHT:-0}" \
  -e MIRROR_REBUILD_CAMERA_HAL="${MIRROR_REBUILD_CAMERA_HAL:-0}" \
  -e MIRROR_CAMERA_FRONT="${MIRROR_CAMERA_FRONT:-0}" \
  -e MIRROR_VIDEO_RAW="${MIRROR_VIDEO_RAW:-1}" \
  -e MIRROR_EXPOSURE_BRIDGE="${MIRROR_EXPOSURE_BRIDGE:-0}" \
  -e MIRROR_GAIN_HEADROOM="${MIRROR_GAIN_HEADROOM:-0}" \
  -v "$repo_root/camera/mirror-camera-metadata.patch:/inputs/camera-metadata.patch:ro" \
  -v "$repo_root/camera/mirror-camera-mount-correction.patch:/inputs/camera-mount-correction.patch:ro" \
  -v "$repo_root/camera/mirror-camera-raw-video.patch:/inputs/raw-video.patch:ro" \
  -v "$repo_root/camera/mirror-codec-video-pack.patch:/inputs/codec-video-pack.patch:ro" \
  -v "$repo_root/camera/mirror-video-pack.h:/inputs/mirror-video-pack.h:ro" \
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
set -eo pipefail
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

if [ "$MIRROR_REBUILD_STAGEFRIGHT" = 1 ]; then
  camera_source=frameworks/av/media/libstagefright/CameraSource.cpp
  if ! grep -q "debug.mirror.video_raw" "$camera_source"; then
    patch "$camera_source" < /inputs/raw-video.patch
  fi
  codec_source=frameworks/av/media/libstagefright/MediaCodecSource.cpp
  if ! grep -q "mirror_pack_venus_nv12" "$codec_source"; then
    patch "$codec_source" < /inputs/codec-video-pack.patch
  fi
  install -m 0644 /inputs/mirror-video-pack.h frameworks/av/media/libstagefright/mirror-video-pack.h
  make -j4 libstagefright libstagefright_32 2>&1 | tee /artifacts/mirror-stagefright-build.log
fi

# Camera HAL is a 32-bit-only secondary-architecture module on this product.
if [ "$MIRROR_REBUILD_CAMERA_HAL" = 1 ]; then
  camera_factory=hardware/qcom/camera/QCamera2/HAL/QCamera2Factory.cpp
  if ! grep -q "ro.mirror.camera.front" "$camera_factory"; then
    patch "$camera_factory" < /inputs/camera-metadata.patch
  fi
  if ! grep -q "Mirror camera metadata: front, mount 0" "$camera_factory"; then
    patch "$camera_factory" < /inputs/camera-mount-correction.patch
  fi
  make -j4 camera.msm8916_32 2>&1 | tee /artifacts/mirror-camera-hal-build.log
fi

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
if [ "$MIRROR_C2D_PROBE" = 1 ]; then
  install -m 0755 /artifacts/libMD2.so out/target/product/msm8916_64/system/vendor/lib/libMD2.so
  install -m 0755 /artifacts/libmmcamera2_c2d_module-probe.so out/target/product/msm8916_64/system/vendor/lib/libmmcamera2_c2d_module.so
fi
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
if [ "$MIRROR_FIRMWARE_AUDIT" = 1 ]; then
  cat >> "$post_boot" <<"FIRMWARE_AUDIT_EOF"

# Read-only inventory of the preserved video firmware, not other partitions.
for mirror_venus_part in venus.mdt venus.b00 venus.b01 venus.b02 venus.b03 venus.b04; do
    log -t MirrorFirmware "$(ls -l /firmware/image/$mirror_venus_part 2>&1)"
    log -t MirrorFirmware "$(md5sum /firmware/image/$mirror_venus_part 2>&1)"
done
FIRMWARE_AUDIT_EOF
fi
if [ "$MIRROR_CAMERA_VERBOSE" = 1 ]; then
  # qti_init_shell cannot set camera_prop under the preserved SELinux policy.
  # Init loads build.prop itself, before the camera service starts.
  sed -i "/^persist.camera.pproc.debug.mask=/d" out/target/product/msm8916_64/system/build.prop
  printf "\npersist.camera.pproc.debug.mask=805306375\n" >> out/target/product/msm8916_64/system/build.prop
else
  sed -i "/^persist.camera.pproc.debug.mask=/d" out/target/product/msm8916_64/system/build.prop
fi
sed -i "/^ro.mirror.camera.front=/d" out/target/product/msm8916_64/system/build.prop
printf "\nro.mirror.camera.front=%s\n" "$MIRROR_CAMERA_FRONT" >> out/target/product/msm8916_64/system/build.prop
case "$MIRROR_VIDEO_RAW" in 0|1) ;; *) echo "MIRROR_VIDEO_RAW must be 0 or 1" >&2; exit 1 ;; esac
case "$MIRROR_EXPOSURE_BRIDGE" in 0|1) ;; *) echo "MIRROR_EXPOSURE_BRIDGE must be 0 or 1" >&2; exit 1 ;; esac
case "$MIRROR_GAIN_HEADROOM" in 0|1) ;; *) echo "MIRROR_GAIN_HEADROOM must be 0 or 1" >&2; exit 1 ;; esac
if [ "$MIRROR_GAIN_HEADROOM" = 1 ] && [ "$MIRROR_EXPOSURE_BRIDGE" != 1 ]; then
  echo "Gain headroom requires the exposure bridge" >&2; exit 1
fi
sed -i "/^debug.mirror.gain_headroom=/d" out/target/product/msm8916_64/system/build.prop
printf "\ndebug.mirror.gain_headroom=%s\n" "$MIRROR_GAIN_HEADROOM" >> out/target/product/msm8916_64/system/build.prop
sed -i "/^debug.mirror.exposure_bridge=/d" out/target/product/msm8916_64/system/build.prop
printf "\ndebug.mirror.exposure_bridge=%s\n" "$MIRROR_EXPOSURE_BRIDGE" >> out/target/product/msm8916_64/system/build.prop
# Persist the tested raw-buffer path across reboots; shell can still override
# this debug property for hardware-encoder investigation without reflashing.
sed -i "/^debug.mirror.video_raw=/d" out/target/product/msm8916_64/system/build.prop
printf "\ndebug.mirror.video_raw=%s\n" "$MIRROR_VIDEO_RAW" >> out/target/product/msm8916_64/system/build.prop
make -j4 snod 2>&1 | tee -a /artifacts/mirror-final-system-build.log

cp out/target/product/msm8916_64/system.img /artifacts/system-mirror-final.img

# Inspect the generated filesystem itself before it leaves the build container.
raw=/tmp/mirror-final-system.raw.img
inspect=/tmp/mirror-final-system
out/host/linux-x86/bin/simg2img /artifacts/system-mirror-final.img "$raw"
mkdir -p "$inspect"
mount -o loop,ro "$raw" "$inspect"
grep -qx "service.adb.tcp.port=5555" "$inspect/build.prop"
grep -qx "ro.mirror.camera.front=$MIRROR_CAMERA_FRONT" "$inspect/build.prop"
grep -qx "debug.mirror.video_raw=$MIRROR_VIDEO_RAW" "$inspect/build.prop"
grep -qx "debug.mirror.exposure_bridge=$MIRROR_EXPOSURE_BRIDGE" "$inspect/build.prop"
grep -qx "debug.mirror.gain_headroom=$MIRROR_GAIN_HEADROOM" "$inspect/build.prop"
if [ "$MIRROR_EXPOSURE_BRIDGE" = 1 ]; then
  grep -a -q "OV5640 target steps=" "$inspect/vendor/lib/libmmcamera_mirror_haf.so"
fi
if [ "$MIRROR_CAMERA_FRONT" = 1 ]; then
  grep -a -q "Mirror camera metadata: front, mount 0" "$inspect/lib/hw/camera.msm8916.so"
  sha256sum "$inspect/lib/hw/camera.msm8916.so"
fi
if [ "$MIRROR_CAMERA_VERBOSE" = 1 ]; then
  grep -qx "persist.camera.pproc.debug.mask=805306375" "$inspect/build.prop"
fi
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
if [ "$MIRROR_REBUILD_STAGEFRIGHT" = 1 ] || [ "$MIRROR_VIDEO_RAW" = 1 ]; then
  for mirror_media_arch in lib lib64; do
    grep -a -q "debug.mirror.video_raw" "$inspect/$mirror_media_arch/libstagefright.so"
    grep -a -q "Mirror recording: refusing oversized input" "$inspect/$mirror_media_arch/libstagefright.so"
    sha256sum "$inspect/$mirror_media_arch/libstagefright.so"
  done
fi
if [ "$MIRROR_C2D_PROBE" = 1 ]; then
  cmp "$inspect/vendor/lib/libMD2.so" /artifacts/libMD2.so
  cmp "$inspect/vendor/lib/libmmcamera2_c2d_module.so" /artifacts/libmmcamera2_c2d_module-probe.so
fi
sha256sum "$inspect/vendor/lib/libmmcamera_ov5640.so" /inputs/libmmcamera_ov5640.so
sha256sum "$inspect/vendor/lib/libmmcamera2_cpp_module.so" /inputs/libmmcamera2_cpp_module.so
sha256sum "$inspect/lib/modules/pronto/pronto_wlan.ko" /inputs/pronto_wlan-stock-kernel.ko
umount "$inspect"
'

shasum -a 256 "$output_image" "$camera_library"
echo "Final system image: $output_image"
echo "Build log: $build_log"
