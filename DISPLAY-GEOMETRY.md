# Physical display versus mirror glass

Owner-confirmed September 15, 2026, with photo `IMG_9720.jpg`.

**Practical layout reference:** with the mirror upright, the screen occupies roughly
the top two-thirds of the mirror. The bottom third is reflection-only. This is the
owner's approximate description for UX planning, not a calibrated measurement.

The LCD occupies only an inset rectangular portion of the mirror. The full outer
glass is larger than the addressable display. The illuminated Android wallpaper
in the reference photo reveals the active rectangle, with reflective-only glass
around it and a notably larger margin at one end. Those margins are physical glass,
not unused desktop pixels or application padding.

- Native panel resolution: 1920×1080; the configured portrait desktop is 1080×1920.
  These describe the LCD, not the dimensions of the entire mirror.
- Apps can draw only inside the LCD rectangle. They cannot place content on the
  surrounding reflective-only area.
- Fullscreen means filling the LCD, not the whole mirror. Do not add artificial
  margins inside the app to reproduce the physical glass margins a second time.
- The photo shows rotated Android content; do not use that rotation as the target
  app orientation. Physical coverage and software orientation are separate concerns.
- Exact LCD/glass dimensions and offsets have not been measured. The photo is
  perspective-distorted, so do not derive calibrated percentages or millimeters
  from it. Measure the glass and active rectangle before building a physical mockup.
- No touchscreen is present. Input belongs on the companion or future voice path.

For UX, preserve black negative space inside the active rectangle to minimize emitted
light and let the reflection remain prominent. Black is not literal transparency;
LCD backlight and mirror optics still affect the result. Test legibility and visual
placement on the real unit, not only a full-window desktop preview.

The original photo remains at the owner's local path `/Users/mj/Downloads/IMG_9720.jpg`.
It is not bundled here because it includes the room reflection; this document records
the relevant hardware observation without publishing the private photo.
