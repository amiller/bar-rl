// Compares the bit-pattern output of streflop's libm functions.
// Compile once for native (in the docker container) and once for WASM,
// run both, diff the outputs. If any function produces different bits on
// WASM vs native, the WASM build's streflop libm is not bit-faithful —
// which explains the demo desyncs.
//
// Build (native, in docker):
//   docker run --rm -v /home/amiller/projects/bar:/work bar-native-build:gcc13 \
//     bash -c 'cd /work/wasm && \
//       g++ -std=c++23 -O3 -ffp-contract=off -DSTREFLOP_SSE \
//         -I/work/repos/RecoilEngine-2025.06.19/rts/lib \
//         -I/work/repos/RecoilEngine-2025.06.19/rts/lib/streflop \
//         scripts/streflop-bits-test.cpp \
//         /work/build-native-2025.06.19/rts/lib/streflop/libstreflop.a \
//         -o build-native-2025.06.19/streflop-bits-test'
//
// Build (wasm):
//   source scripts/wasm-env.sh && \
//     em++ -std=c++23 -O3 -ffp-contract=off -DSTREFLOP_SSE -msimd128 \
//       -I../repos/RecoilEngine-2025.06.19/rts/lib \
//       -I../repos/RecoilEngine-2025.06.19/rts/lib/streflop \
//       scripts/streflop-bits-test.cpp \
//       build-wasm-2025.06.19/rts/lib/streflop/libstreflop.a \
//       -o build-wasm-browser/streflop-bits-test.js \
//       -sNODERAWFS=1 -sEXIT_RUNTIME=1
//
// Run both and diff stdout.

#include "streflop_cond.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static uint32_t bits(float f) {
    uint32_t u; std::memcpy(&u, &f, 4); return u;
}

static void dump1(const char* name, float (*fn)(float), float x) {
    float r = fn(x);
    std::printf("%-12s(%-+18.10g) = %-+18.10g  [bits 0x%08x]\n",
                name, (double)x, (double)r, bits(r));
}

static void dump2(const char* name, float (*fn)(float, float), float x, float y) {
    float r = fn(x, y);
    std::printf("%-12s(%-+18.10g, %-+18.10g) = %-+18.10g  [bits 0x%08x]\n",
                name, (double)x, (double)y, (double)r, bits(r));
}

int main() {
    using namespace math;

    // Inputs span small/large/tricky values.
    const float xs[] = {
        0.0f, -0.0f, 1.0f, -1.0f, 0.5f, 1.0e-30f, 1.0e30f,
        3.14159265f, 6.28318530f, 1.57079632f,
        12345.6789f, -12345.6789f,
        0.123456789f, 123.456789f,
    };
    const int N = sizeof(xs)/sizeof(xs[0]);

    std::printf("=== floor ===\n");
    for (int i = 0; i < N; i++) dump1("floor", math::floor, xs[i]);

    std::printf("\n=== ceil ===\n");
    for (int i = 0; i < N; i++) dump1("ceil",  math::ceil,  xs[i]);

    std::printf("\n=== sqrt ===\n");
    for (int i = 0; i < N; i++) if (xs[i] >= 0) dump1("sqrt",  math::sqrt,  xs[i]);

    std::printf("\n=== sinf ===\n");
    for (int i = 0; i < N; i++) dump1("sinf",  math::sinf,  xs[i]);

    std::printf("\n=== cosf ===\n");
    for (int i = 0; i < N; i++) dump1("cosf",  math::cosf,  xs[i]);

    std::printf("\n=== fmod ===\n");
    for (int i = 0; i < N; i++)
        dump2("fmod", math::fmod, xs[i], 6.28318530f);

    std::printf("\nDONE\n");
    return 0;
}
