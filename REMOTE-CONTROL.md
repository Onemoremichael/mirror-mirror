# Mirror Remote

The MIRROR panel is not a touchscreen. This local service turns a Mac
connected by USB into a control bridge for Safari on the same Mac or an iPhone
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

This bridge is intentionally local. Direct Android ADB over Wi-Fi is not the
dependable path on this Android 6 build; the Mac's authorized USB connection
is.
