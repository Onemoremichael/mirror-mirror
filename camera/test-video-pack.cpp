#include "mirror-video-pack.h"
#include <assert.h>
#include <stdio.h>
#include <vector>

static void check(unsigned w, unsigned h) {
    size_t stride = (w + 127u) & ~127u, yRows = (h + 31u) & ~31u;
    size_t uvRows = (h / 2u + 15u) & ~15u;
    size_t allocation = (stride * (yRows + uvRows) + 20480 + 4095) & ~(size_t)4095;
    size_t tight = (size_t)w * h * 3 / 2;
    std::vector<uint8_t> input(allocation, 0xee), output(tight + 32, 0xcd);
    for (unsigned row = 0; row < h; ++row)
        for (unsigned col = 0; col < w; ++col)
            input[row * stride + col] = (row + col) % 173;
    for (unsigned row = 0; row < h / 2; ++row)
        for (unsigned col = 0; col < w; ++col)
            input[stride * yRows + row * stride + col] = 40 + (row + col) % 131;
    assert(!mirror_pack_venus_nv12(output.data(), tight - 1, input.data(), allocation, w, h));
    assert(!mirror_pack_venus_nv12(output.data(), tight, input.data(), allocation - 1, w, h));
    assert(!mirror_pack_venus_nv12(output.data(), tight, input.data(), allocation + 1, w, h));
    for (size_t i = 0; i < output.size(); ++i) assert(output[i] == 0xcd);
    assert(mirror_pack_venus_nv12(output.data(), tight, input.data(), allocation, w, h) == tight);
    for (unsigned row = 0; row < h; ++row)
        for (unsigned col = 0; col < w; ++col) assert(output[row * w + col] == (row + col) % 173);
    for (unsigned row = 0; row < h / 2; ++row)
        for (unsigned col = 0; col < w; ++col)
            assert(output[w * h + row * w + col] == 40 + (row + col) % 131);
    for (size_t i = tight; i < output.size(); ++i) assert(output[i] == 0xcd);
    printf("PASS %ux%u: %zu padded -> %zu packed bytes\n", w, h, allocation, tight);
}
int main() {
    check(1280, 720); check(1920, 1080); check(640, 480); check(642, 482);
    uint8_t byte = 0;
    assert(!mirror_pack_venus_nv12(&byte, 1, &byte, 1, 0, 2));
    assert(!mirror_pack_venus_nv12(&byte, 1, &byte, 1, 4098, 2));
    assert(!mirror_pack_venus_nv12(&byte, 1, &byte, 1, 3, 2));
    assert(!mirror_pack_venus_nv12(NULL, 1, &byte, 1, 2, 2));
}
