#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")" && pwd)
sdk_root="${ANDROID_SDK_ROOT:-/Users/mj/Library/Android/sdk}"
java_root="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
build_tools="$sdk_root/build-tools/35.0.0"
android_jar="$sdk_root/platforms/android-35/android.jar"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mirror-probe.XXXXXX")
key_dir="$repo_root/.work/clock-signing"
trap 'rm -rf "$build_dir"' EXIT
export JAVA_HOME="$java_root"
mkdir -p "$build_dir/classes" "$build_dir/dex" "$repo_root/artifacts/android-apps" "$key_dir"
"$build_tools/aapt" package -f -M "$repo_root/camera/probe/AndroidManifest.xml" -I "$android_jar" -F "$build_dir/base.apk"
"$java_root/bin/javac" --release 8 -classpath "$android_jar" -d "$build_dir/classes" "$repo_root/camera/probe/ProbeActivity.java"
"$java_root/bin/jar" cf "$build_dir/classes.jar" -C "$build_dir/classes" .
"$build_tools/d8" --lib "$android_jar" --min-api 23 --output "$build_dir/dex" "$build_dir/classes.jar"
(cd "$build_dir/dex" && "$build_tools/aapt" add "$build_dir/base.apk" classes.dex)
"$build_tools/zipalign" -f 4 "$build_dir/base.apk" "$build_dir/aligned.apk"
if [[ ! -f "$key_dir/debug.keystore" ]]; then
  "$java_root/bin/keytool" -genkeypair -keystore "$key_dir/debug.keystore" -storepass android -keypass android -alias androiddebugkey -dname 'CN=Mirror Development' -keyalg RSA -keysize 2048 -validity 10000
fi
"$build_tools/apksigner" sign --ks "$key_dir/debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$repo_root/artifacts/android-apps/camera-probe-debug.apk" "$build_dir/aligned.apk"
"$build_tools/apksigner" verify "$repo_root/artifacts/android-apps/camera-probe-debug.apk"
