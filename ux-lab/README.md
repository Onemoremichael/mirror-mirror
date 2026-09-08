# Afterglow — orbital clock

A responsive clock on pure black, supporting portrait and landscape. Sparse geocentric-inspired rings, slow orbiting
points and a small epicycle surround the time. This is decorative geometry, not
an astronomical model. The display contains only the time, with no branding,
navigation, captions or status text. The mirror itself supplies the background.
The Android clock has been visually tested on the physical Mirror in portrait
and landscape. LCD glow and legibility can still vary with room lighting.

Run `node ux-lab/server.mjs` from the repository root, then open
http://localhost:8766. Double-click the clock display for fullscreen where
supported. The clock uses America/New_York time in 12-hour format so the recovered
Mirror's GMT default does not affect it.

The terminal prints the Mac’s LAN address for the phone remote at `/remote`.
Both devices must be on the same network. The remote offers Orbit, Still,
Clock only, three colors and low glow. Keys 1–3 provide the same mode choices
on a computer. Reduced-motion preferences disable the animation.

All viewers share temporary in-memory settings. The prototype has no external
assets, dependencies, camera/audio use, or Android commands. Its server listens
on the LAN at port 8766; keep it local. The existing Android remote is separate
at port 8765. Chromium 44 compatibility is provided for the Android app; see
[the app build instructions](../clock-app/README.md).
