// Compare float-to-short cast results for out-of-range values.
// CCobInstance::WindChanged does `short(heading * RAD2TAANG)` where
// heading*RAD2TAANG can reach 65535 — out of [-32768, 32767], so the cast
// is implementation-defined. Different bits on WASM vs native => the wind
// generator gets different COB SetDirection arg => cradle target rotation
// diverges. Test plausible windHeading*RAD2TAANG values.
#include <cstdio>
#include <cstdint>

int main() {
    // RAD2TAANG = 32768/PI ~= 10430.37835
    constexpr float RAD2TAANG = 10430.37835f;
    // Sample windHeading values across [0, 2*PI)
    const float headings[] = {
        0.0f, 0.5f, 1.0f, 1.57f, 2.0f, 3.0f, 3.14159f,
        3.5f, 4.0f, 4.5f, 5.0f, 5.5f, 6.0f, 6.28f,
        6.283185f
    };
    for (float h : headings) {
        const float p = h * RAD2TAANG;
        const short s = short(p);   // <-- implementation-defined for |p|>32767
        std::printf("heading=%-+18.10g  product=%-+15.6g  short=%6d  uint16=%5u\n",
                    (double)h, (double)p, s, (unsigned)(uint16_t)s);
    }
    return 0;
}
