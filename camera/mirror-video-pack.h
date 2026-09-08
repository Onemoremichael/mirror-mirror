#ifndef MIRROR_VIDEO_PACK_H
#define MIRROR_VIDEO_PACK_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Matches msm_media_info.h's linear NV12 Venus layout (not tiled/UBWC).
// Exact allocation match is intentional: unknown layouts must fail closed.
static inline size_t mirror_pack_venus_nv12(uint8_t *dst, size_t capacity,
        const uint8_t *src, size_t size, unsigned width, unsigned height) {
    if (!dst || !src || !width || !height || width > 4096 || height > 4096
            || (width & 1) || (height & 1)) return 0;
    const size_t stride = (width + 127u) & ~127u;
    const size_t yRows = (height + 31u) & ~31u;
    const size_t uvRows = (height / 2u + 15u) & ~15u;
    const size_t expected = (stride * (yRows + uvRows) + 20480u + 4095u) & ~(size_t)4095u;
    const size_t tight = (size_t)width * height * 3u / 2u;
    if (size != expected || capacity < tight) return 0;
    for (unsigned row = 0; row < height; ++row)
        memcpy(dst + (size_t)row * width, src + (size_t)row * stride, width);
    for (unsigned row = 0; row < height / 2u; ++row)
        memcpy(dst + (size_t)width * height + (size_t)row * width,
               src + stride * yRows + (size_t)row * stride, width);
    return tight;
}
#endif
