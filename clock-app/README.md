# Afterglow Android foundation

Package `dev.mirror.clock`, launcher name **Afterglow**. A small Java Activity
embeds the orbital clock in an immersive WebView, defaulting to portrait. Android Home remains
Launcher3; Back exits the app. No camera, microphone, native JavaScript bridge,
boot receiver, or device administration is involved. The window stays awake
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
