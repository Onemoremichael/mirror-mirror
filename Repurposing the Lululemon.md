# Rooting / Repurposing the Lululemon "Mirror" Model One (APQ8016E) — A First-Principles Guide

> **Observed-unit update (2026-09-03):** USB and Sahara reconnaissance has now
> identified `HWID 0x007060e100000000` and public-key hash
> `35ac01e7ee8478261aea5134e07e45cb6c5621d42716c15bb10dee0c53d65759`.
> This is **not** the common Qualcomm unfused-development hash cited below.
> Treat this unit as requiring an exact signed Firehose programmer unless a
> later secure-boot query proves otherwise. The earlier “almost certainly
> unfused” assessment was a hypothesis and is contradicted by this evidence.
> No partition writes have been attempted.

## TL;DR
- **Root the stock Android on the original board — don't flash a custom OS.** The Snapdragon 410E (APQ8016E) in the Model One is almost certainly an *unfused* (secure-boot-disabled) part, which means its bootloader chain accepts self-signed images and — critically — Qualcomm EDL (9008) mode gives you a full, unbrickable read/write path to the eMMC. Rooting stock Android preserves the working driver for the Samsung LTI400HN01 LVDS panel; flashing DragonBoard/postmarketOS images will almost certainly break the display because that panel needs a custom DSI-to-LVDS bridge driver that no generic image ships.
- **Your attack ladder, least to most invasive:** (1) ADB over the USB port, (2) fastboot unlock, (3) 1.8 V UART serial console (the single highest-value step), (4) EDL/9008 full eMMC dump + Magisk-patched boot re-flash, (5) direct eMMC/JTAG as last resort. Take a **full EDL backup before writing anything** — that is your safety net.
- **Realistic outcome:** rooted stock Android running a browser/MagicMirror kiosk app is the likely best case and is very achievable given how open this hardware is. Full custom OS with working display is possible but a large device-tree project. If everything fails, the community fallback — a ~$24 generic HDMI/LVDS controller board — still works.

---

## Key Findings

1. **This is a well-known repurposing target, but no one has rooted *this* board.** Two community teardowns exist (mdthats.me and the olm3ca/mirror GitHub project). Both concluded the Android mainboard is effectively abandoned by software but physically open and modular — the mdthats teardown notes "nothing about the hardware feels dead or locked down, it's the software layer that's abandoned." Neither achieved root on the APQ8016E board; both fell back to bypassing it with a third-party TV/LVDS controller board. A separate XDA thread ("Lululemon Mirror") is about a *newer i.MX8-based* Mirror generation (that user found "U-Boot output but cannot write to UART" and could "dump RAM" via JTAG but not flash) — useful methodology, but a different SoC. So you would be doing genuinely novel work on the APQ8016E Model One.

2. **The SoC is extremely well-documented.** The APQ8016E is the same silicon as the DragonBoard 410c reference board, with full public LK/aboot bootloader source (Linaro/CodeAurora), U-Boot support, Linaro Debian, Android 5.1, mainline Linux (msm8916-mainline), and postmarketOS. That means firehose programmers, signing tools, and bootloader knowledge are all public.

3. **Secure boot is very likely OFF.** MSM8916 consumer and embedded parts frequently ship unfused. EDL tooling reports a default public-key hash `0xcc3153a80293939b90d02d3bf8b23e0292e452fef662c74998421adad42a380f` on unfused MSM8916/8909 devices, with `Auth_Enabled: False`. If your unit reports this, you can self-sign and flash a custom aboot/LK and the whole device is open. Trusted-Firmware-A's Qualcomm MSM8916 port documentation states verbatim: *"The DragonBoard 410c does not have secure boot enabled by default"* — i.e., unfused is the normal state for this silicon family. (That same doc warns the port "is not secure... the hardware used for memory protection is not described in the APQ8016E documentation.")

4. **The display is the whole payoff, and it argues for the least-invasive path.** The MSM8916 outputs MIPI DSI. A 40" 1080p LVDS panel (LTI400HN01) requires a DSI-to-LVDS bridge chip (Toshiba TC358775 at I²C 0x0f, or TI SN65DSI83/84 at 0x2c/0x2d) on the Mirror's board. The stock kernel already has the exact driver + timings + backlight config for this panel. A generic custom OS does not. **Keep the stock kernel; just get root.**

---

## Details

### 1. Platform background: APQ8016E / Snapdragon 410E

The **APQ8016E** is the embedded/IoT variant of the Snapdragon 410 (MSM8916 family): quad-core 64-bit ARM Cortex-A53 up to 1.2 GHz, Adreno 306 GPU, on a 28 nm process. The "APQ" prefix means **no cellular modem** (vs. "MSM" phone parts); the "E" denotes the embedded SKU. Qualcomm announced the 410E and 600E on **September 28, 2016**, stating they "are being made available globally by third party distributors, initially through Arrow Electronics, for a minimum of 10 years" from the mobile version's first commercial sample (i.e., until 2025). At launch, CNX-Software reported you could buy the Snapdragon 410E on Arrow "for $17.28 for one unit, and as low as $11.50 per unit for 1K order." It targets exactly this kind of product — digital signage, set-top boxes, kiosks. The Mirror is essentially signage hardware, which is precisely how both teardown authors described the internals.

The Adreno 306 GPU supports OpenGL ES 3.0, OpenCL 1.1, and DirectX 9.3 but **lacks Vulkan entirely**, and official AOSP support for the platform ends at **Android 7.1 (Nougat)** — both relevant to what a modern browser/PWA kiosk can realistically do.

**Why this matters for hackability:** because the identical SoC powers the **DragonBoard 410c** 96Boards reference board, everything about the boot chain is public:
- LK/aboot bootloader source (Linaro Qualcomm Landing Team git, tags like `ubuntu-qcom-dragonboard410c-LA.BR.1.2.4`).
- A **U-Boot** port that can *replace* LK in the aboot partition — built with `make dragonboard410c_defconfig`. Per Das U-Boot's official docs, "Although the DragonBoard 410c does not have secure boot set up by default, the firmware still expects firmware ELF images to be 'signed'... it provides the firmware with some required metadata" (you self-sign with qtestsign).
- OS images: Linaro Debian, Android 5.1.1 (Linux 3.10.49 downstream kernel), OpenEmbedded/Yocto, Arch Linux ARM, Windows 10 IoT Core.
- Mainline Linux via **msm8916-mainline** and **postmarketOS**. Per Nikita Travkin's FOSDEM 2022 talk "Running Mainline Linux on Snapdragon 410" (subtitled "How we support over 25 devices in postmarketOS"), UART, USB, eMMC/SD, WiFi/BT, and GPU/display all work — but the postmarketOS wiki is explicit that "There are many different display panels and each needs a custom panel driver." All MSM8916 devices in postmarketOS use **lk2nd** as a secondary bootloader.

**Boot chain:** PBL (in SoC ROM) → SBL1 → aboot (LK) → Android boot.img/kernel. Each stage verifies the next **only if** secure-boot fuses are blown.

**Secure boot & how to check it.** Qualcomm secure boot works by blowing QFPROM eFuses that store the SHA-256 hash of the OEM root certificate (OEM_PK_HASH). At each boot stage the code hashes the image's root cert and compares to the fused hash. **If the fuses were never blown, the SoC reads a known default hash and skips root-cert validation — secure boot is effectively disabled.** As one detailed writeup of an unfused Qualcomm device puts it: "When the eFuses have not been blown, the system reads a default value for the public key hash, which signifies a 'non-secure' state. The phone then knows it is in an insecure mode and consequently skips the final validation of the root certificate's legitimacy." Three ways to determine status on your unit:
- **In fastboot** (if available): `fastboot getvar secure` → `secure: no` means not enforced.
- **In EDL/Sahara**: bkerler/edl prints the `PK_HASH`. The value `0xcc3153a80293939b90d02d3bf8b23e0292e452fef662c74998421adad42a380f` is the default seen across unfused MSM8916/8909 units; the `secureboot` sub-command shows `Auth_Enabled: False` for each Sec_Boot region. bkerler's own writeup notes that if the tool reports secure boot disabled, the device's firmware can be freely modified.
- **Trusted-Firmware-A** confirms unfused is the norm for this family (quoted above).

If secure boot **is** enforced on your unit (unique PK_HASH, `Auth_Enabled: True`, `fastboot getvar secure` = yes), you cannot flash custom bootloaders — but you can still read the eMMC in EDL and, if the stock build is debuggable, get root without changing the bootloader.

### 2. Access vectors, least to most invasive

**(a) ADB over USB.** The mdthats teardown notes an "unused terminal for a USB connection" on the mic board, and the board has USB. The i.MX8 sibling Mirror enumerated as `Bus 001 Device … ID 18d1:4ee7 Google Inc. Nexus/Pixel Device (charging + debug)` over USB — evidence these Mirrors expose an ADB gadget. Plug a USB-A-to-A cable or OTG adapter into any exposed USB port and run `adb devices`.
- If it shows `unauthorized`, you need to accept the RSA prompt — hard with no display, but if the build is debuggable (`ro.adb.secure=0`) it will authorize automatically. As Android's own recovery docs state, unauthenticated adb works when "bootloader is unlocked (ro.boot.verifiedbootstate is orange) or debuggable build" AND "ro.adb.secure has a value of 0."
- If it shows `device`, run `adb shell`, then `getprop ro.build.type` (user vs userdebug), `getprop ro.debuggable`, `getprop ro.secure`, `getprop ro.build.version.release` (likely Android 5.1/6.0/7.x for a 2018 410E build). A userdebug/eng build gives you `adb root` immediately, since "adb root works in development builds only (i.e. eng and userdebug which have ro.debuggable=1 by default)."
- If ADB doesn't appear at all, the vendor may have removed the adbd socket — go to UART.

**(b) Fastboot.** `adb reboot bootloader`, then `fastboot devices`. Try `fastboot oem device-info`, then `fastboot oem unlock` or `fastboot flashing unlock`. **Caveat specific to this silicon:** Qualcomm's LK disables most fastboot commands on `user` builds via a top-level makefile flag — `ifeq ($(TARGET_BUILD_VARIANT),user) CFLAGS += -DDISABLE_FASTBOOT_CMDS=1`. When set, `flash`, `erase`, `boot`, and `oem unlock` are all compiled out. If so, fastboot is a dead end and you move to EDL.

**(c) UART serial console — the highest-value step.** Qualcomm boards expose a debug UART (blsp_uart) that prints the entire boot log and often drops to an LK/aboot prompt or a shell.
- **CRITICAL: Qualcomm UART is 1.8 V logic.** A standard 3.3 V/5 V FTDI cable can damage the SoC pin and won't read cleanly. You must use a **1.8 V-capable** adapter (see shopping list). The DragonBoard docs specify a step-up cable (FTDI `TTL-232RG-VREG1V8-WE`) precisely because "a standard USB TTL FTDI cable... that steps up the 1.8 volts available on the DB410c is required."
- Baud is **115200 8N1** (kernel cmdline `console=ttyMSM0,115200n8`).
- Find the pads: look for a group of 3–4 test points/vias near the SoC or PMIC, sometimes silkscreened TX/RX/GND/RXD/TXD. Confirm GND with a multimeter in continuity mode against a shield/ground. Find TX by watching for a pin that idles high (at 1.8 V) and **pulses during power-on** ("the voltage fluctuates for a few seconds and then stabilizes at the VCC value... the device sends serial data through that TX pin for debugging"). RX is usually the adjacent quiet pin. A logic analyzer + PulseView lets you measure the bit width to confirm baud before you connect.
- What the log reveals: SBL version, "Secure boot" status line, LK/aboot version, the kernel command line (including `androidboot.verifiedbootstate` and whether `ro.boot.secure` is set), and DTB/board-id. If autoboot can be interrupted, you may get an aboot/LK fastboot prompt; if the kernel console is a getty and the build is debuggable, you may get a root shell directly.

**(d) Qualcomm EDL / 9008 mode — the unbrickable path.** EDL is a SoC-ROM download mode. Enter it via `adb reboot edl`, `fastboot oem edl`, or by **shorting two EDL test points to ground while applying power** (on MSM8916 boards these are usually a pair of pads near the eMMC/SoC, often shorted with tweezers or a jumper as USB is connected). The XDA poster on the sibling board found pads labeled `PROG` — on your APQ8016E board, look for a similar labeled/unlabeled pad pair. Once in 9008:
- The host sees a "Qualcomm HS-USB QDLoader 9008" device.
- You upload a signed **Firehose programmer** (`prog_emmc_firehose_8916.mbn`) via the **Sahara** protocol (the bootrom stage that uploads the loader into RAM); **Firehose** then does full eMMC read/write.
- **Signed 8916 firehose programmers are widely available** — extracted from dozens of shipping MSM8916 phones and mirrored publicly (e.g. `github.com/OneLabsTools/Programmers/prog_emmc_firehose_8916.mbn`, plus Hovatek and mobilerdx collections). This is the single most important enabler: the eMMC is fully readable/writable regardless of ADB/fastboot state. A real MSM8916 EDL session confirms the flow: "sahara - Uploading loader prog_emmc_firehose_8916.mbn... Successfully uploaded programmer :). firehose_client - Target detected: MSM8916."
- **Tools:** `bkerler/edl` (open-source Python, Linux/Win/Mac) is the recommended client; QFIL/QPST (Qualcomm, Windows) is the alternative.

Example edl.py commands (Linux):
```
# detect + read secure-boot state
edl --loader=prog_emmc_firehose_8916.mbn printgpt
edl secureboot --loader=prog_emmc_firehose_8916.mbn
# FULL BACKUP FIRST — dump everything
edl rl BACKUPS --genxml --loader=prog_emmc_firehose_8916.mbn
# or per-partition
edl r boot boot.img --loader=prog_emmc_firehose_8916.mbn
edl r aboot aboot.img --loader=prog_emmc_firehose_8916.mbn
# later, write a patched image
edl w boot magisk_patched.img --loader=prog_emmc_firehose_8916.mbn
```

**(e) JTAG.** MSM8916 boards can expose JTAG; the sibling-board hacker used JTAG to dump RAM but couldn't easily dump flash. Tools: Riff Box, OpenOCD, JTAGulator (to find pins). Treat as last resort — EDL is easier and does what JTAG would.

**(f) Direct eMMC.** In-circuit "ISP" pads or desoldering the Micron MCP for a BGA reader. **High risk here specifically** because the Micron package is a **multi-chip package (LPDDR + eMMC combined)** — the teardown identified it as a Micron MCP (marking "8ZA92 JZ099") holding both RAM and flash, so desoldering risks destroying the RAM too. Only consider if the eMMC is otherwise dead. EDL makes this unnecessary in nearly all cases.

### 3. What to do once you have access

**Best case (secure boot off, which is likely):**
1. Full EDL dump of all partitions (`edl rl BACKUPS --genxml`).
2. Extract `boot.img`, examine `default.prop`/`init.rc` for `ro.debuggable`, `ro.secure`, `ro.adb.secure`, `persist.sys.usb.config`, `ro.build.type`.
3. If not already debuggable: unpack boot.img, edit `default.prop` to `ro.secure=0`, `ro.adb.secure=0`, `ro.debuggable=1`, `persist.sys.usb.config=adb`, repack, and re-flash via EDL. This alone gives you an authorized root ADB shell (these are the standard properties that convert a `user` build's behavior to `userdebug`).
4. Or patch boot.img with **Magisk** (Magisk app → "Select and Patch a File" → stock boot.img → flash the resulting `magisk_patched.img` to the boot partition via EDL or fastboot). Magisk patching works on Android 5/6/7-era boot images without TWRP.
5. With root on stock Android, **install a kiosk browser / MagicMirror² client / Fully Kiosk Browser APK** and point it at a local MagicMirror instance. The stock display driver keeps the panel working. Note: an Android 5–7 WebView is old, lacks Vulkan, and the platform's AOSP line ends at 7.1 — so modern PWAs may need a sideloaded up-to-date browser (a compatible Chromium/Firefox APK), and some heavy web apps won't run. MagicMirror² itself is lightweight HTML/JS and should be fine.

**If you want a full custom OS (higher effort, display risk):** You'd port a device tree for this exact board — the DSI-to-LVDS bridge (identify whether it's a TC358775 at I²C 0x0f or an SN65DSI8x at 0x2c/0x2d), the panel timings, backlight (the teardown shows a discrete LED backlight driver + T-CON board), touch (there is none — it's phone-controlled), audio (TI TPA3116D2 class-D amp, CX20921 far-field mic DSP), and camera (OmniVision OV5640). msm8916-mainline provides `linux-mdss-dsi-panel-driver-generator` (generates a DRM panel driver from the downstream device tree's panel init sequence) and `lk2nd` to help, but this is a multi-week reverse-engineering project. Recommended only if you enjoy the journey.

### 4. Reconnaissance checklist (what to look for physically)
- Photograph both sides of the mainboard at high resolution; pop the shield cans (the teardown confirms the SoC, Micron MCP, PM8916, and WCN3660B live under cans).
- Hunt for **3–4-pad UART groups** near the SoC/PMIC; silkscreen TX/RX/GND is a bonus.
- Hunt for **2-pad EDL/PROG test-point pairs** near the eMMC/SoC.
- Check every unpopulated header/connector — embedded/signage boards routinely leave debug headers depopulated (the teardown explicitly noted "plenty of free space" and unpopulated terminals).
- Use a multimeter (continuity for GND, DC volts to profile TX) and a cheap logic analyzer to confirm UART and measure baud before connecting a serial adapter.

### 5. Step-by-step attack plan with go/no-go gates
1. **Power on, observe.** Does it boot to the stock loading screen? (Confirms board is alive; the mdthats unit "powers on just fine" and shows a loading screen.) Zero risk.
2. **Try USB/ADB** on every port. `adb devices`. **GO** if `device`/`unauthorized`; note state.
3. **Open, photograph, identify chips.** Zero risk.
4. **Find + attach 1.8 V UART.** Capture full boot log at 115200. **This is the key intelligence step.**
5. **Read the log:** secure-boot status, LK version, cmdline, build type. Decide path.
6. **Try fastboot unlock** (`adb reboot bootloader` → `fastboot oem unlock`). GO if it works; NO-GO (commands stripped) → EDL.
7. **Enter EDL, upload 8916 firehose, `printgpt` + `secureboot`.** Confirm secure-boot state and partition map.
8. **FULL EDL BACKUP.** Do not proceed to any write until this completes and is verified. This is the brick-proofing step.
9. **Analyze firmware** (unpack boot.img with `unpackbootimg`/Android Image Kitchen, `binwalk`, check props).
10. **Patch + reflash** (props edit or Magisk) via EDL/fastboot. Test. If it bricks, re-enter EDL and restore your backup.

### 6. Interpreting the boot log
- A line like `Secure boot: 0` / "Secure boot disabled," or the absence of cert-failure messages = unfused, flash freely.
- `androidboot.verifiedbootstate=orange` in the cmdline = unlocked/unverified boot (good).
- LK/aboot version tells you which CodeAurora tag to cross-reference for fastboot command availability.
- Kernel `console=ttyMSM0,115200n8` confirms UART port/baud.

---

## Recommendations

**Stage 0 — buy the kit** (see list) and take a full set of board photos before touching anything.

**Stage 1 — non-destructive recon (do first, always).** Power on and observe; try ADB on every USB port; check `ro.debuggable`/`ro.secure`/`ro.build.type` if you get a shell. **Decision gate:** if ADB gives a root/userdebug shell, skip straight to Stage 4 (root the stock ROM) — you may not need to open anything further.

**Stage 2 — UART.** Solder fine wire to the UART pads, capture the boot log at 1.8 V/115200. **Decision gate:** the log tells you secure-boot state and whether fastboot/EDL are reachable. This single step de-risks everything after it.

**Stage 3 — establish the unbrickable path.** Enter EDL, load the 8916 firehose, and take a **complete eMMC backup** before any write. **Do not skip this.** Benchmark to proceed: a verified full backup exists on your PC.

**Stage 4 — get root on stock Android** (the recommended end state): props patch or Magisk-patched boot.img, reflashed via EDL/fastboot. Then sideload Fully Kiosk Browser + MagicMirror². This preserves the LVDS display driver.

**Stage 5 — only if you want the challenge:** attempt a custom OS (postmarketOS/mainline) with a hand-built device tree for the DSI-LVDS bridge and panel.

**Thresholds that change the plan:**
- If `fastboot getvar secure` = `yes` / unique PK_HASH / `Auth_Enabled: True` → secure boot is enforced; **abandon custom-bootloader plans**, pursue only debuggable-build root or shell, and rely on the HDMI/LVDS fallback for display if root fails.
- If ADB is fully removed AND UART gives no writable console AND fastboot commands are stripped → EDL is your only foothold; a props/Magisk reflash via EDL is still viable.
- If the eMMC or MCP is physically dead → HDMI/LVDS controller-board fallback (below).

**Fallback (guaranteed to work):** ignore the SoC entirely and drive the panel with a generic controller board. The olm3ca/mirror project documents this for both the BOE-panel Rev08 units and, via Issue #8, the older **LTI400HN01 / LM40SAMFHD700AG25WV** panel using a generic HDMI/DP/VGA LVDS controller board (about $23.55–$24 on eBay/AliExpress) plus a matching LVDS cable, feeding it from a Raspberry Pi or mini PC running MagicMirror. One eBay buyer of that exact board wrote, "I bought this to repurpose my Lulu Lemmon 'Mirror.'" This is the proven community outcome and your insurance policy. Note the strategic downside: it leaves the SoC unused and requires an external Pi/PC, whereas rooting the stock board would run MagicMirror on the device itself and keep the original display driver.

---

## Tools & shopping list (approx. 2026 prices)

**Essential**
- **1.8 V-capable USB-UART adapter — DSD TECH SH-U09C5** (FTDI FT232-based; supports 5 V/3.3 V/2.5 V/**1.8 V**), ~$14. This is the correct part for Qualcomm's 1.8 V console. (Alternatives: FTDI `TTL-232RG-VREG1V8-WE` cable per DragonBoard docs; a CP2102N/FT232H board with VIO tied to 1.8 V.)
- **Multimeter** (continuity + DC volts), $15–40.
- **Cheap 8-ch 24 MHz logic analyzer** ("Saleae clone"), ~$10–15, with PulseView/sigrok.
- **Fine-tip soldering iron**, enameled/magnet wire (~AWG 34–38) for tacking to pads, good **flux**, ~$40–80 total.
- **Magnifier or USB microscope**, $30–100.
- **USB cables:** USB-A-to-A, micro-USB, and OTG adapters.
- **Linux laptop** for adb/fastboot/edl.py (EDL drivers are simplest on Linux).

**Optional / last resort**
- **JTAGulator** (~$200) for finding UART/JTAG pins automatically.
- Bus Pirate (~$30) as a probe.
- eMMC/BGA programmer (EasyJTAG + eMMC socket) + hot-air rework station — only for dead-flash recovery; high risk on the combined RAM+flash MCP.

**Software (all free/open-source unless noted)**
- Android **platform-tools** (adb/fastboot).
- **bkerler/edl** (`github.com/bkerler/edl`) — Sahara/Firehose client.
- **QFIL/QPST** (Qualcomm, Windows) — alternative EDL client.
- Signed **`prog_emmc_firehose_8916.mbn`** (public mirrors, e.g. `github.com/OneLabsTools/Programmers`).
- **Magisk** (`github.com/topjohnwu/Magisk`) for root.
- **qtestsign** (`github.com/msm8916-mainline/qtestsign`) to self-sign LK/U-Boot if you go custom. (Note its own warning: "Most Qualcomm devices available in production have firmware secure boot permanently enabled... They will fail to boot when flashing modified firmware!" — which is exactly why you verify fuse status first.)
- **lk2nd** and **msm8916-mainline/linux** + `linux-mdss-dsi-panel-driver-generator` if attempting mainline.
- boot-image tools: `unpackbootimg`/Android Image Kitchen, `binwalk`, `abootimg`.
- serial terminal: `minicom`/`screen`/`picocom`.

---

## Risks & realistic expectations

**Likelihood by tier (my assessment, given how open this hardware is):**
- Shell access via UART or ADB: **high** — Qualcomm always has a debug UART, and these Mirrors have shown ADB gadgets.
- Full EDL eMMC dump: **very high** — 8916 firehose is public; 9008 is a ROM feature that can't be locked out.
- Root on stock Android (props/Magisk reflash): **high, conditional** on secure boot being off (likely) OR the build being debuggable.
- Custom bootloader / custom OS with working display: **low-to-moderate** — feasible if unfused, but the panel device-tree work is substantial.
- Bricking permanently: **low** — as long as EDL/9008 works and you took a full backup, you can always restore. EDL is the "unbrickable" recovery path on Qualcomm.

**Effort/time:** recon + UART + EDL backup: a focused weekend. Rooting stock + kiosk app: another day or two. Custom OS with display: weeks.

**Honest uncertainty flags:**
- I could not find *anyone* who has rooted this specific APQ8016E Model One board — the two teardowns stopped at "too hard, use a TV board," and the detailed XDA rooting thread is a *different, newer i.MX8* Mirror. Treat all SoC-specific steps as first-principles extrapolation from DragonBoard 410c / general MSM8916 practice.
- Whether *your* unit's secure-boot fuses are blown is unknown until you check (`fastboot getvar secure` or EDL PK_HASH). Curiouser was a small startup building signage-like hardware; unfused is plausible but not guaranteed.
- The exact UART/EDL pad locations are undocumented for this board — you'll have to find them by probing.
- Which DSI-LVDS bridge chip is on the board is unconfirmed (TC358775 vs SN65DSI8x) — it matters only if you go the custom-OS route.
- Context: Lululemon acquired Mirror (Curiouser Products) for $500M in 2020, took a $442.7M impairment in Q4 2022, and in September 2023 announced it would discontinue the hardware and hand content to Peloton, continuing service only for existing subscribers. New-account creation is closed, which is exactly why the stock software is now a dead end and repurposing is the only path.

**Bottom line:** get root on the stock ROM via EDL + Magisk/props, keep the stock display driver, and run a kiosk browser. It's the shortest path to a working AI smart mirror and it sidesteps the one genuinely hard problem (the LVDS panel). Keep the ~$24 controller-board plan as your guaranteed fallback.
