/* Temporary single-client diagnostic: sample packed input, forward unchanged. */
#include <dlfcn.h>
#include <stdio.h>
#include <android/log.h>
#include "c2d2.h"

typedef C2D_STATUS (*update_fn)(uint32, uint32, C2D_SURFACE_TYPE, void *);

C2D_STATUS c2dUpdateSurface(uint32 id, uint32 bits,
    C2D_SURFACE_TYPE type, void *definition)
{
    static update_fn real_update;
    static unsigned samples;
    if (!real_update) {
        void *real_lib = dlopen("libC2D2.so", RTLD_NOW);
        if (real_lib) real_update = (update_fn)dlsym(real_lib, "c2dUpdateSurface");
    }
    if (!real_update) return C2D_STATUS_NOT_SUPPORTED;
    if (definition && (bits & C2D_SOURCE) && (type & C2D_SURFACE_YUV_HOST)) {
        C2D_YUV_SURFACE_DEF *s = definition;
        unsigned n = __sync_add_and_fetch(&samples, 1);
        if ((n == 1 || n == 10) && s->plane0 && s->width && s->height &&
            s->width <= 5184 && s->height <= 4096 &&
            s->stride0 >= (int)(s->width * 2) && s->stride0 <= 16384) {
            unsigned y, x, parity;
            const unsigned char *p = s->plane0;
            __android_log_print(ANDROID_LOG_INFO, "MirrorC2DProbe",
                "INPUT sample=%u id=%u fmt=%u width=%u height=%u stride=%d",
                n, id, s->format, s->width, s->height, s->stride0);
            /* Both packed byte parities avoid assuming YUYV versus UYVY. */
            for (parity = 0; parity < 2; parity++) for (y = 0; y < 48; y++) {
                char row[129];
                unsigned sy = y * s->height / 48;
                for (x = 0; x < 64; x++) {
                    unsigned sx = x * s->width / 64;
                    unsigned char v = p[sy * s->stride0 + sx * 2 + parity];
                    static const char hex[] = "0123456789abcdef";
                    row[x*2] = hex[v>>4]; row[x*2+1] = hex[v&15];
                }
                row[128] = 0;
                __android_log_print(ANDROID_LOG_INFO, "MirrorC2DProbe",
                    "ROW sample=%u parity=%u y=%u %s", n, parity, y, row);
            }
        }
    }
    return real_update(id, bits, type, definition);
}
