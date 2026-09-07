# Mirror Remote

The MIRROR panel is not a touchscreen. This local service turns a Mac
connected by USB or authorized Wi-Fi ADB into a control bridge for Safari on the same Mac or an iPhone
on the same Wi-Fi.

## Install

Keep the MIRROR's internal USB data cable connected to the Mac, then run:

```sh
brew install android-platform-tools scrcpy node
./install-mirror-remote.sh
```

The service starts immediately and at future Mac logins. It also asks macOS to
keep the computer awake while it is on external power.

## Open

- On the Mac: `http://127.0.0.1:8765`
- On an iPhone: use the LAN address printed by the installer, currently
  `http://192.168.0.29:8765`

Both devices must be on the same Wi-Fi. The remote opens directly with no
account or access-key prompt. It is meant for a trusted home network and is not
exposed to the Internet.

This Mac relay is distinct from the dashboard site hosted by the MIRROR on
port 8787. The relay needs no code. The dashboard site uses the four-digit PIN
shown under its QR and remembers paired phone browsers.

## Controls

- Tap the live image to click Android controls.
- Drag across the image to swipe.
- Use **Back**, **Home**, and **Recent** from the sticky phone navigation bar.
- Use the D-pad and **OK** for interfaces that respond better to keyboard-like
  navigation.
- **Wake** turns on the panel and dismisses its credential-free keyguard.
- **Mirror dashboard** and **Android settings** open those apps directly.
- **Afterglow clock** opens or reloads the experimental clock app.
- **App menu** opens Afterglow's page address, reload, bundled-mode and
  portrait/landscape settings.
- **Mac view** launches a native `scrcpy` window on the Mac.

The dashboard is optional. Launcher3 remains Android's normal home screen.

## Troubleshooting

Check that Android is visible to the Mac:

```sh
adb devices -l
```

The expected USB serial is `be9d0af` with state `device`. If Safari says the
MIRROR is offline, reconnect the USB data cable and restart ADB:

```sh
adb kill-server
adb start-server
```

Reinstall/restart the controller after changing its source:

```sh
./install-mirror-remote.sh
```

Logs are stored at `~/Library/Logs/mirror-remote.log` and
`~/Library/Logs/mirror-remote-error.log`.

The Wi-Fi connection at `192.168.0.51:5555` was verified authorized on September
6, 2026. USB remains a fallback if network ADB becomes unavailable.

The screen preview is a sequence of screenshots, not a video stream. A complex
1920×1080 screen produced a roughly 4 MB PNG and took about 13 seconds to capture
and transfer over Wi-Fi. Captures have a 30-second timeout, and simultaneous
requests share a single capture. A delayed preview does not necessarily mean
Android is offline; navigation controls can still work. The connection badge
checks device reachability separately.
