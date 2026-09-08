#ifndef MIRROR_EXPOSURE_PLAN_H
#define MIRROR_EXPOSURE_PLAN_H
#include <stdint.h>

/* Pure register-plan builder, not an I/O interface. Android advertises 1/6 EV
 * steps. Scale the observed stock target window, preserving exact zero-EV
 * values. AEC enable, gain ceiling, frame timing and clock registers are never
 * included. Register roles corroborated by Linux ov5640_set_ae_target(). */
struct mirror_exposure_register { uint16_t address; uint8_t value; };
static inline int mirror_exposure_plan(int steps,
        struct mirror_exposure_register output[6]) {
    static const uint16_t addresses[6] = {0x3a0f,0x3a10,0x3a1b,0x3a1e,0x3a11,0x3a1f};
    static const uint8_t baseline[6] = {0x30,0x28,0x30,0x26,0x60,0x14};
    static const uint16_t scale[25] = {1024,1149,1290,1448,1625,1825,2048,2299,2580,2896,3251,3649,4096,4598,5161,5793,6502,7298,8192,9195,10321,11585,13004,14596,16384};
    unsigned i;
    if (!output || steps < -12 || steps > 12) return 0;
    for (i = 0; i < 6; ++i) {
        unsigned value = ((unsigned)baseline[i] * scale[steps + 12] + 2048) / 4096;
        output[i].address = addresses[i];
        output[i].value = value > 255 ? 255 : value;
    }
    return 1;
}
#endif
