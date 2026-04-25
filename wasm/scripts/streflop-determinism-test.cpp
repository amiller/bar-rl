// Test bit-determinism of streflop's vendored libm + SpringMath helpers
// across native (gcc) and WASM (emcc) builds.
//
// Build native:  g++ -O3 -ffp-contract=off -DSTREFLOP_SSE \
//                  -I .../rts -I .../rts/lib/streflop \
//                  streflop-determinism-test.cpp libstreflop.a -o test-native
// Build WASM:    em++ -O3 -ffp-contract=off -DSTREFLOP_SSE -msimd128 \
//                  -I .../rts -I .../rts/lib/streflop \
//                  streflop-determinism-test.cpp libstreflop.a -o test.js
//
// Each invocation prints one line per test case as "<name> <bits>" where
// <bits> is the float result reinterpreted as uint32_t (bit-exact comparison).
// Diffing the outputs of native and wasm runs locates any differing op.
//
// Streflop must already be compiled for the target — link against the
// libstreflop.a that the engine build produced (e.g. build-wasm/.../libstreflop.a
// for WASM, or a native streflop build).

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>

#define STREFLOP_SSE
#include "streflop.h"

namespace streflop {
    constexpr float TWOPI = 6.28318530717958647692f;
}

static inline uint32_t bits(float f) {
    uint32_t u;
    __builtin_memcpy(&u, &f, sizeof u);
    return u;
}

// Simplified ClampRad — same logic as SpringMath.inl
static float ClampRad(float f) {
    f += 0.0f;
    f = f - streflop::TWOPI * streflop_libm::__floorf(f / streflop::TWOPI);
    return f;
}

int main() {
    // Inputs span the range an animation tick would produce.
    const float TWOPI = streflop::TWOPI;
    float test_inputs[] = {
        0.0f, 1.0f, 1.5f, 2.0f, 3.14159265f, TWOPI, 5.0f, 7.0f, 7.85206f,
        10.0f, 100.0f, 1000.0f, 12345.678f, 0.0833f, 0.16667f, 1e-7f, -1.0f
    };
    int n = sizeof(test_inputs) / sizeof(*test_inputs);

    for (int i = 0; i < n; ++i) {
        float x = test_inputs[i];
        printf("clamp_rad(%.7f) = %u\n", x, bits(ClampRad(x)));
    }

    for (int i = 0; i < n; ++i) {
        float x = test_inputs[i];
        printf("sin(%.7f)        = %u\n", x, bits(streflop_libm::__sinf(x)));
        printf("cos(%.7f)        = %u\n", x, bits(streflop_libm::__cosf(x)));
        printf("atan2(%.4f,1.0)  = %u\n", x, bits(streflop_libm::__ieee754_atan2f(x, 1.0f)));
        printf("floor(%.4f)      = %u\n", x, bits(streflop_libm::__floorf(x)));
        printf("fmod(%.4f,2pi)   = %u\n", x, bits(streflop_libm::__ieee754_fmodf(x, TWOPI)));
        printf("sqrt(|%.4f|)     = %u\n", x, bits(streflop_libm::__ieee754_sqrtf(x < 0.0f ? -x : x)));
    }

    // Accumulator pattern (mirrors the per-frame anim tick).
    float acc = 0.0f;
    for (int frame = 0; frame < 200; ++frame) {
        acc = ClampRad(acc + 0.0833333f);
        if (frame % 10 == 9) {
            printf("acc[f=%d]         = %u\n", frame, bits(acc));
        }
    }
    return 0;
}
