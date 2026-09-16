# Afterglow Android foundation

Package `dev.mirror.clock`, launcher name **Afterglow**. A small Java Activity
embeds the orbital clock in an immersive WebView, defaulting to portrait. Android Home remains
Launcher3; Back exits the app. No camera, native JavaScript bridge,
boot receiver, or device administration is involved. An opt-in native microphone/
speaker adapter is available for Looking Glass (below). The window stays awake
while the app is foregrounded.

## Build and install

Prerequisites: OpenJDK 17, Android SDK platform 35 and build-tools 35.0.0. The
script uses the existing Mac SDK by default; override `ANDROID_SDK_ROOT` and
`JAVA_HOME` for a different installation. It has no Gradle/network dependencies.

```sh
./mirror-build-clock.sh
adb -s 192.168.0.51:5555 install -r artifacts/android-apps/afterglow-debug.apk
adb -s 192.168.0.51:5555 shell am start -n dev.mirror.clock/.ClockActivity \
  --es url http://192.168.0.29:8766/
```

The local development signing key lives in `.work/clock-signing/debug.keystore`.
Preserve it to install updates without uninstalling. The APK is a development
build signed with a local debug key, not a production/distribution release.

## Experiment

Run `node ux-lab/server.mjs` on the Mac. Edit the HTML, CSS and JavaScript in
`ux-lab/`, then select **Afterglow clock** in the Android remote to reload.
The **App menu** button opens native settings for the page address, reload,
bundled mode, portrait/landscape orientation and exit. The directional pad and text entry work without touch.
The page address and orientation are remembered. You can also pass
`--es orientation portrait` or `--es orientation landscape` when launching.
The phone's visual controls are at the Mac's
LAN address on port 8766, path `/remote`.

On initial launch without a page address, the app uses its bundled clock. If
a configured page fails to load (including HTTP errors or a 12-second timeout),
it falls back to the bundled clock and retries the live address after a minute.
An already loaded clock also continues ticking if the Mac disconnects; remote
scene controls reconnect when the server returns.

Explicit bundled mode:

```sh
adb -s 192.168.0.51:5555 shell am start -n dev.mirror.clock/.ClockActivity --ez offline true
```

Rebuild the APK to update its bundled assets. Live page changes only need a
reload. The older Chromium 44 engine receives a CSS compatibility stylesheet
for custom properties and clock sizing. The font uses Android's thin family.
Time is displayed in `America/New_York`, including daylight saving, because
the recovered Android image defaults to GMT. Change `ux-lab/app.js` to change
the home timezone.

## Looking Glass native audio (September 16, 2026)

Afterglow now declares RECORD_AUDIO and MODIFY_AUDIO_SETTINGS. Ordinary launches
remain display-only. Launch with `--ez audioBridge true` to attach a foreground-only
native audio endpoint to device loopback:8782. This flag is not saved. The Mac's
Looking Glass server must be running, with both USB tunnels configured:

```sh
adb -s be9d0af shell pm grant dev.mirror.clock android.permission.RECORD_AUDIO
adb -s be9d0af reverse tcp:8780 tcp:8780
adb -s be9d0af reverse tcp:8782 tcp:8782
adb -s be9d0af shell am force-stop dev.mirror.clock
adb -s be9d0af shell am start -n dev.mirror.clock/.ClockActivity \
  --es url 'http://127.0.0.1:8780/?timeZone=America%2FNew_York' \
  --es orientation portrait --ez audioBridge true
```

Select **Mirror · USB** in the Mac companion and explicitly Start conversation.
Only then does native AudioRecord open. AudioTrack plays replies on STREAM_MUSIC
at the existing volume. A native five-bar conversation glyph breathes in teal while
listening and turns warm gold during audible replies, reacting to audio levels.
Muted input uses a static amber pause glyph and “Muted” label. It disappears when
capture stops and respects Android's animator-duration scale being disabled.
Accessibility descriptions distinguish listening, speaking/suppression, and mute.
The small overlay draws at about 30 fps only while active; no WebView animation or
additional network audio data is required. End releases
capture; leaving the Activity or losing the connection also stops it. No audio is
saved and no cloud keys are present in the APK. No JavaScript microphone bridge.

PCM is 16 kHz mono signed little-endian, 20 ms packets. Current echo safety is
half-duplex: audible response frames gate captured audio plus a 350 ms tail;
silent response frames do not gate it. Wait for the reply before speaking again.
Native and network queues are bounded, and only a loopback USB endpoint is used.
Do not expose the Mac audio port to a LAN or the internet.

Build/install and native input/output transport were verified on Android 6.0.1.
A short Live session closed with confirmed usage; the owner subsequently confirmed
the spoken Mirror interaction worked. Far-field and echo robustness still need
testing. See `../looking-glass/docs/MIRROR-AUDIO.md` for implementation,
controls, limitations and test evidence. Prior installed APK is backed up locally
at ignored `.work/afterglow-before-native-audio.apk`; no firmware was changed.
