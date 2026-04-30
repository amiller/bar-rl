// Test bit-determinism of the engine's REAL synced-path math functions
// (math::sqrt, fastmath::sqrt_sse, fastmath::sin, fastmath::cos), which go
// through SSE intrinsics — NOT through streflop libm. This is what gets
// called from GetObstacleAvoidanceDir, .Normalize(), .Length(), etc.
//
// The original streflop-determinism-test.cpp only tested streflop_libm::*,
// which is bit-faithful between native and wasm. But the engine doesn't
// actually CALL streflop::sqrt — FastMath.h:226 overrides math::sqrt with
// fastmath::sqrt_sse → _mm_sqrt_ss. That's the un-tested path.
//
// Build native (with SSE):
//   g++ -O3 -ffp-contract=off -msse2 \
//       -I .../rts -I .../rts/lib/streflop \
//       sse-paths-test.cpp .../libstreflop.a -o sse-test-native
// Build wasm (emcc SSE2 shim → wasm-simd):
//   em++ -O3 -ffp-contract=off -msimd128 -msse2 \
//       -I .../rts -I .../rts/lib/streflop \
//       sse-paths-test.cpp .../libstreflop.a -o sse-test-wasm.js

#include <cstdint>
#include <cstdio>
#include <cmath>

#define STREFLOP_SSE
#include "streflop.h"
#include <emmintrin.h>  // _mm_sqrt_ss et al

static inline uint32_t bits(float f) {
    uint32_t u;
    __builtin_memcpy(&u, &f, sizeof u);
    return u;
}

// Replicas of the engine's hot-path inlines from FastMath.h.
namespace fm {
    static inline float sqrt_sse(float x) {
        __m128 vec = _mm_set_ss(x);
        vec = _mm_sqrt_ss(vec);
        return _mm_cvtss_f32(vec);
    }
    static inline float isqrt2_nosse(float x) {
        float xh = 0.5f * x;
        int32_t i; __builtin_memcpy(&i, &x, 4);
        i = 0x5f375a86 - (i >> 1);
        __builtin_memcpy(&x, &i, 4);
        x = x * (1.5f - xh * (x * x));
        x = x * (1.5f - xh * (x * x));
        return x;
    }
    // PI constants matching MathConstants.h
    static constexpr float PI       = 3.14159265358979323846f;
    static constexpr float TWOPI    = 6.28318530717958647692f;
    static constexpr float INVPI2   = 1.0f / TWOPI;
    static constexpr float HALFPI   = PI / 2.0f;
    static constexpr float NEGHALFPI= -HALFPI;
    static constexpr float PIU4     = 4.0f / PI;
    static constexpr float PISUN4   = -4.0f / (PI * PI);

    static inline float sin(float x) {
        x = x - ((int)(x * INVPI2)) * TWOPI;
        if (x > HALFPI) x = -x + PI;
        else if (x < NEGHALFPI) x = -x - PI;
        x = PIU4 * x + PISUN4 * x * (x < 0 ? -x : x);
        x = 0.225f * (x * (x < 0 ? -x : x) - x) + x;
        return x;
    }
    static inline float cos(float x) { return fm::sin(x + HALFPI); }
}

int main() {
    streflop::streflop_init<streflop::Simple>();

    // Inputs spanning normal sim ranges plus edge-y stuff.
    float test_inputs[] = {
        0.0f, 0.5f, 1.0f, 1.5f, 2.0f, 3.14159265f, fm::TWOPI,
        5.0f, 7.85206f, 10.0f, 100.0f, 1000.0f, 12345.678f,
        0.0833f, 0.16667f, 1e-7f, 1e-30f, 1e30f
    };
    int n = sizeof(test_inputs)/sizeof(*test_inputs);

    puts("# fastmath::sqrt_sse — what math::sqrt actually maps to");
    for (int i = 0; i < n; ++i) {
        float x = test_inputs[i];
        if (x < 0) continue;
        printf("sqrt_sse(%.7f)   = %u\n", x, bits(fm::sqrt_sse(x)));
    }

    puts("# fastmath::isqrt2_nosse — what math::isqrt maps to (synced!)");
    for (int i = 0; i < n; ++i) {
        float x = test_inputs[i];
        if (x <= 0) continue;
        printf("isqrt2(%.7f)     = %u\n", x, bits(fm::isqrt2_nosse(x)));
    }

    puts("# fastmath::sin / fastmath::cos — sometimes used in synced code");
    for (int i = 0; i < n; ++i) {
        float x = test_inputs[i];
        printf("fm_sin(%.7f)     = %u\n", x, bits(fm::sin(x)));
        printf("fm_cos(%.7f)     = %u\n", x, bits(fm::cos(x)));
    }

    // Vector ops: the most common avoidance-path computation is
    //   d = sqrt(dx*dx + dz*dz);   then  ux = dx/d; uz = dz/d.
    // We mimic that for a handful of (dx,dz) pairs.
    puts("# Vector3::Length & Normalize equivalents");
    float pairs[][2] = {
        {1.0f, 1.0f}, {3.0f, 4.0f}, {0.001f, 0.999f},
        {120.0f, 35.5f}, {-7.5f, 0.0008f}, {1e-3f, 1e-3f}
    };
    for (int i = 0; i < (int)(sizeof(pairs)/sizeof(*pairs)); ++i) {
        float dx = pairs[i][0], dz = pairs[i][1];
        float d2 = dx*dx + dz*dz;
        float d = fm::sqrt_sse(d2);
        float ux = dx / d, uz = dz / d;
        printf("len(%.4f,%.4f) d=%u ux=%u uz=%u\n",
               dx, dz, bits(d), bits(ux), bits(uz));
    }

    // Accumulator: simulate 200 frames of "sum of normalized vectors" — what
    // the obstacle-avoidance loop does over neighbors.
    float ax = 0, az = 0;
    for (int f = 0; f < 200; ++f) {
        float dx = 1.0f + 0.001f * f;
        float dz = 0.5f - 0.001f * f;
        float d  = fm::sqrt_sse(dx*dx + dz*dz);
        ax += dx / d;
        az += dz / d;
        if (f % 20 == 19)
            printf("acc[f=%d] ax=%u az=%u\n", f, bits(ax), bits(az));
    }
    return 0;
}
