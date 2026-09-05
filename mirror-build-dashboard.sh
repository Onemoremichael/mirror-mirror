#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")" && pwd)
upstream=https://github.com/TimStewartJ/lululemon-mirror-repurpose.git
upstream_commit=d11f32b4f525e9cc3f7c674ebd47a8553b4ff19a
patch_file="$repo_root/patches/lululemon-mirror-landscape.patch"
artifact_dir="$repo_root/artifacts/android-apps"
output_apk="$artifact_dir/mirror-home-landscape-debug.apk"
java_home=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
android_home="$HOME/Library/Android/sdk"
source_dir=$(mktemp -d "${TMPDIR:-/tmp}/mirror-dashboard.XXXXXX")
trap 'rm -rf "$source_dir"' EXIT

if [[ ! -x "$java_home/bin/java" ]]; then
  echo "OpenJDK 17 is required (brew install openjdk@17)." >&2
  exit 1
fi
if ! command -v sdkmanager >/dev/null 2>&1; then
  echo "Android command-line tools are required." >&2
  exit 1
fi

mkdir -p "$android_home" "$artifact_dir"
export JAVA_HOME="$java_home"
export ANDROID_HOME="$android_home"
export ANDROID_SDK_ROOT="$android_home"

sdkmanager --sdk_root="$android_home" \
  'platform-tools' 'platforms;android-35' 'build-tools;35.0.0' >/dev/null
git clone --quiet "$upstream" "$source_dir/source"
git -C "$source_dir/source" checkout --quiet --detach "$upstream_commit"
git -C "$source_dir/source" apply "$patch_file"

(
  cd "$source_dir/source"
  ./gradlew :android:mirror-home:testDebugUnitTest \
    :android:mirror-home:assembleDebug
)
cp "$source_dir/source/android/mirror-home/build/outputs/apk/debug/mirror-home-debug.apk" \
  "$output_apk"

shasum -a 256 "$output_apk"
echo "Dashboard APK: $output_apk"
