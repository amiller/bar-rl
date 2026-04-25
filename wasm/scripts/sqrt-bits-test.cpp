// Tests bit-equality of math::sqrt (which routes to fastmath::sqrt_sse,
// using _mm_sqrt_ss intrinsic) and math::isqrt (fastmath::isqrt2_nosse,
// pure bit-trick + Newton). These are the most plausible WASM-vs-native
// mismatches given our findings so far (wind generator anim diverges).
//
// Build native (in docker):
//   docker run --rm -v /home/amiller/projects/bar:/work bar-native-build:gcc13 \
//     g++ -std=c++23 -O3 -ffp-contract=off -DSTREFLOP_SSE \
//       -I/work/repos/RecoilEngine-2025.06.19/rts \
//       -I/work/repos/RecoilEngine-2025.06.19/rts/lib \
//       -I/work/repos/RecoilEngine-2025.06.19/rts/lib/streflop \
//       /work/wasm/scripts/sqrt-bits-test.cpp \
//       -o /work/wasm/build-native-2025.06.19/sqrt-bits-test
//
// Build wasm:
//   source scripts/wasm-env.sh && \
//     em++ -std=c++23 -O3 -ffp-contract=off -DSTREFLOP_SSE -msimd128 \
//       -I../repos/RecoilEngine-2025.06.19/rts \
//       -I../repos/RecoilEngine-2025.06.19/rts/lib \
//       -I../repos/RecoilEngine-2025.06.19/rts/lib/streflop \
//       -include cstdlib -include cmath \
//       scripts/sqrt-bits-test.cpp \
//       -o build-wasm-2025.06.19/sqrt-bits-test.js \
//       -sNODERAWFS=1 -sEXIT_RUNTIME=1

#include "System/FastMath.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static uint32_t bits(float f) {
    uint32_t u; std::memcpy(&u, &f, 4); return u;
}

int main() {
    const float xs[] = {
        0.0f, 1.0f, 0.25f, 0.5f, 4.0f, 16.0f, 100.0f, 12345.6f,
        1.0e-10f, 1.0e10f, 0.123456789f, 9.87654321f,
        // values from wind-vec lengths in the BAR engine. Wind dir is in
        // [-maxStrength, maxStrength]; strengths typically 0..40
        2.0f, 5.0f, 10.0f, 25.0f, 40.0f, 1.5f, 7.5f, 13.7f, 28.3f,
    };
    const int N = sizeof(xs)/sizeof(xs[0]);

    std::printf("=== math::sqrt (=> fastmath::sqrt_sse via _mm_sqrt_ss) ===\n");
    for (int i = 0; i < N; i++) {
        float r = math::sqrt(xs[i]);
        std::printf("sqrt(%-+18.10g) = %-+18.10g  bits=0x%08x\n",
                    (double)xs[i], (double)r, bits(r));
    }

    std::printf("\n=== math::isqrt (=> fastmath::isqrt2_nosse, bit-trick + Newton) ===\n");
    for (int i = 0; i < N; i++) {
        float r = math::isqrt(xs[i]);
        std::printf("isqrt(%-+18.10g) = %-+18.10g  bits=0x%08x\n",
                    (double)xs[i], (double)r, bits(r));
    }

    return 0;
}
