#!/usr/bin/env bash
set -euo pipefail

# The same file is the macOS entry point and the container build recipe. This
# keeps the exact Docker mounts and compatibility config reproducible instead
# of relying on a command copied from terminal history.
if [[ "${MIRROR_WIFI_IN_CONTAINER:-0}" != 1 ]]; then
    repo_root=$(cd "$(dirname "$0")" && pwd)
    source_image="$repo_root/.work/mirror-android-build.ext4.img"
    running_config="$repo_root/artifacts/android-m-msm8916_64/running-kernel-build.config"
    artifact_dir="$repo_root/artifacts/android-m-msm8916_64"

    for required in "$source_image" "$running_config"; do
        if [[ ! -f "$required" ]]; then
            echo "Missing Wi-Fi build input: $required" >&2
            exit 1
        fi
    done
    mkdir -p "$artifact_dir"
    docker run --rm --platform linux/amd64 --privileged \
        -e MIRROR_WIFI_IN_CONTAINER=1 \
        -v "$source_image:/build.img" \
        -v "$running_config:/running-kernel.config:ro" \
        -v "$artifact_dir:/artifacts" \
        -v "$repo_root/mirror-build-running-kernel-wifi.sh:/mirror-build-wifi.sh:ro" \
        alleen/apq8016_bm bash /mirror-build-wifi.sh
    shasum -a 256 "$artifact_dir/pronto_wlan-stock-kernel.ko"
    exit 0
fi

build_image=/build.img
source_root=/mnt/build
kernel_out="$source_root/out/kernel-running-mirror"
cross_compile="$source_root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
wifi_source="$source_root/vendor/qcom/opensource/wlan/prima"
artifact_dir=/artifacts

mkdir -p "$source_root" "$artifact_dir"
mount -o loop "$build_image" "$source_root"
trap 'umount "$source_root"' EXIT

rm -rf "$kernel_out"
mkdir -p "$kernel_out"
cp /running-kernel.config "$kernel_out/.config"

# Match the stock kernel's externally visible release exactly. The running
# config uses CONFIG_LOCALVERSION_AUTO, but its original Git object is not in
# the public tree, so encode the observed suffix and turn the automatic suffix
# off for this compatibility build.
"$source_root/kernel/scripts/config" --file "$kernel_out/.config" \
    --set-str LOCALVERSION '-perf-gf46dad5260f' \
    --disable LOCALVERSION_AUTO

make -C "$source_root/kernel" O="$kernel_out" \
    ARCH=arm64 CROSS_COMPILE="$cross_compile" olddefconfig
make -C "$source_root/kernel" O="$kernel_out" -j4 \
    ARCH=arm64 CROSS_COMPILE="$cross_compile"

make -C "$source_root/kernel" O="$kernel_out" -j4 \
    ARCH=arm64 CROSS_COMPILE="$cross_compile" \
    M="$wifi_source" \
    WLAN_ROOT="$wifi_source" MODNAME=wlan BOARD_PLATFORM=msm8916 \
    CONFIG_PRONTO_WLAN=m modules

cp "$wifi_source/wlan.ko" "$artifact_dir/pronto_wlan-stock-kernel.ko"
cp "$kernel_out/Module.symvers" "$artifact_dir/Module-stock-kernel.symvers"
cp "$kernel_out/.config" "$artifact_dir/running-kernel-build.config"

modinfo "$artifact_dir/pronto_wlan-stock-kernel.ko"
