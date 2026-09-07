#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
source_library="$repo_root/.work/android-m/vendor/qcom/proprietary/prebuilt_HY22/target/product/msm8916_64/system/vendor/lib/libmmcamera2_cpp_module.so"
output_library="$repo_root/artifacts/android-m-msm8916_64/libmmcamera2_cpp_module-mirror.so"
objdump="$repo_root/.work/android-m/prebuilts/gcc/darwin-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-objdump"
expected_source_sha=94ce0a02766a34ed62f7eee08eb78ea573af2002f45cca8fa70ce98103ec6a7e
patch_offset=$((0x80b8))

for required in "$source_library" "$objdump"; do
  if [[ ! -f "$required" ]]; then
    echo "Missing required input: $required" >&2
    exit 1
  fi
done

actual_source_sha=$(shasum -a 256 "$source_library" | awk '{print $1}')
if [[ "$actual_source_sha" != "$expected_source_sha" ]]; then
  echo "Refusing to patch an unknown CPP library: $actual_source_sha" >&2
  exit 1
fi

source_bytes=$(xxd -p -l 2 -s "$patch_offset" "$source_library")
if [[ "$source_bytes" != 90e0 ]]; then
  echo "Unexpected bytes at 0x80b8: $source_bytes (expected 90e0)" >&2
  exit 1
fi

mkdir -p "$(dirname "$output_library")"
cp "$source_library" "$output_library"

# cpp_module_handle_streamon_event asks the upstream statistics module for an
# AEC update after the downstream stream-on has completed. This board's YUV
# sensor owns AEC/AWB itself, so that optional query returns an error. The
# legacy HY22 library incorrectly propagates it as a fatal stream-on failure.
# Retarget only the failure-path cleanup branch from 0x81dc to 0x81da, where
# the existing code sets the return value to success before the same cleanup.
printf '\217\340' | dd of="$output_library" bs=1 seek="$patch_offset" conv=notrunc status=none

patched_bytes=$(xxd -p -l 2 -s "$patch_offset" "$output_library")
if [[ "$patched_bytes" != 8fe0 ]]; then
  echo "Patch verification failed: $patched_bytes" >&2
  exit 1
fi

disassembly=$(
  "$objdump" -d --start-address=0x8090 --stop-address=0x81e0 "$output_library"
)
if ! grep -Eq '80b8:.*e08f.*b\.n.*81da' <<<"$disassembly"; then
  echo "Patched branch does not decode as the expected jump to 0x81da" >&2
  exit 1
fi
if ! grep -Eq '809e:.*da0c.*bge\.n.*80ba' <<<"$disassembly"; then
  echo "Normal success branch changed unexpectedly" >&2
  exit 1
fi

shasum -a 256 "$source_library" "$output_library"
echo "Patched CPP library: $output_library"
