#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")" && pwd)
docker run --rm --platform linux/amd64 --privileged \
  -v "$repo_root/.work/mirror-android-build.ext4.img:/build.img" \
  -v "$repo_root/camera/mirror-snapcam-preview.patch:/inputs/preview.patch:ro" \
  -v "$repo_root/camera/mirror-snapcam-video-preview.patch:/inputs/video-preview.patch:ro" \
  -v "$repo_root/camera/mirror-snapcam-video-rotation.patch:/inputs/video-rotation.patch:ro" \
  -v "$repo_root/camera/mirror-snapcam-video-bitrate.patch:/inputs/video-bitrate.patch:ro" \
  -v "$repo_root/camera/mirror-snapcam-photo-rotation.patch:/inputs/photo-rotation.patch:ro" \
  -v "$repo_root/camera/mirror-snapcam-photo-front-rotation.patch:/inputs/photo-front-rotation.patch:ro" \
  -v "$repo_root/artifacts/android-m-msm8916_64:/artifacts" \
  alleen/apq8016_bm bash -lc '
set -eo pipefail
mkdir -p /mnt/build
mount -o loop /build.img /mnt/build
cleanup() { sync; cd /; umount /mnt/build; }
trap cleanup EXIT
cd /mnt/build
source build/envsetup.sh >/dev/null
lunch msm8916_64-userdebug >/dev/null
app=packages/apps/SnapdragonCamera
if ! grep -q "mMirrorSensorAspectRatio" "$app/src/com/android/camera/PhotoUI.java"; then
  (cd "$app" && patch -p1 < /inputs/preview.patch)
fi
if ! grep -q "private int getCaptureRotation" "$app/src/com/android/camera/PhotoModule.java"; then
  (cd "$app" && patch -p1 < /inputs/photo-rotation.patch)
fi
if ! grep -q "Front preview is mirrored; saved JPEG is not" "$app/src/com/android/camera/PhotoModule.java"; then
  (cd "$app" && patch -p1 < /inputs/photo-front-rotation.patch)
fi
if ! grep -q "mMirrorSensorAspectRatio" "$app/src/com/android/camera/VideoUI.java"; then
  (cd "$app" && patch -p1 < /inputs/video-preview.patch)
fi
if ! grep -q "Mirror video rotation=" "$app/src/com/android/camera/VideoModule.java"; then
  (cd "$app" && patch -p1 < /inputs/video-rotation.patch)
fi
if ! grep -q "Mirror 720p recording bitrate=" "$app/src/com/android/camera/VideoModule.java"; then
  (cd "$app" && patch -p1 < /inputs/video-bitrate.patch)
fi
make -j4 SnapdragonCamera 2>&1 | tee /artifacts/mirror-snapcam-build.log
cp out/target/product/msm8916_64/system/app/SnapdragonCamera/SnapdragonCamera.apk /artifacts/SnapdragonCamera-mirror.apk
sha256sum /artifacts/SnapdragonCamera-mirror.apk
'
