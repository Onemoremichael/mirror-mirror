# Looking Glass application boundary

Looking Glass's starter product scope is time/date, timers, to-dos, weather,
read-only calendar review, and display controls. Its `docs/CAPABILITIES.md` and
runtime catalog distinguish working local functions from planned integrations.
Novel researched experiences (such as weekly Gators schedules) are composed,
then optionally saved/forked. Hardware recovery remains separate from these features.

Update September 16, 2026: Looking Glass is a practical voice-controlled assistant.
Its foundation includes persistent timers/to-dos, request clarification, saved/forked
capability configurations, GPT-Live-1 conversation and Agents API outcome planning.
Voice can use the Mac or the new opt-in native USB Mirror microphone/speaker bridge.
Native transport and spoken interaction were verified, including the owner's
weather-follow-up test; far-field and echo quality need broader testing.
See [Afterglow audio setup](clock-app/README.md#looking-glass-native-audio-september-16-2026).
Common timer and weather requests use guarded local fast paths; eligible successful
planner actions can nominate narrowly constrained reusable shortcuts.
Weather uses Open-Meteo, up to five saved cities, Fahrenheit/Celsius, a timestamped
cache and stale/unavailable states. Calendar and web research remain unconnected.

The application lives in the separate
[looking-glass repository](https://github.com/Onemoremichael/looking-glass), locally
at `../looking-glass`. See its `docs/PLAN.md` for the staged build and
`docs/INTEGRATION.md` for the current interface.

This repository remains responsible for Android recovery, hardware drivers,
camera compatibility, diagnostics, and the general-purpose remote. Looking Glass
owns personality, visuals, conversation state, API integration, and its eventual app.

Looking Glass runs on Mac port 8780, with its companion at `/remote`. Its output-only
display has been verified on the existing Afterglow wrapper in Android 6.0.1 portrait.
USB ADB reverse forwarding is the verified transport; see Looking Glass's
`docs/INTEGRATION.md` for launch and frontend-refresh commands. Display-only operation
needed no new APK; native audio requires the updated Afterglow APK and mic permission,
but no firmware changes. The application server does not operate ADB or activate the camera.
Android Home remains unchanged; the existing remote on 8765 and clock lab on 8766
remain separate. Android upgrades and full-duplex interruption remain future work.

Weather visuals use large type, black negative space, a contrasting forecast strip,
transparent generated artwork and subtle independent rain streaks. Small forecast
art remains static; reduced-motion is supported. This is designed for the existing
non-touch display and its [top-two-thirds physical coverage](DISPLAY-GEOMETRY.md).

Future hardware work should be driven by measured needs: especially full-duplex
microphone/speaker echo behavior, legacy WebView performance, and explicit one-shot
camera capture. Current camera limitations remain as documented in
[camera/README.md](camera/README.md). No firmware work is required by the initial plan.
