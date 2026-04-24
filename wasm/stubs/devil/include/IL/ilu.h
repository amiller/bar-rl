/* Minimal DevIL ilu (image utility) stub. Bitmap.cpp uses ilBuildMipmaps
 * which in real DevIL lives in ilu; keep it in the IL namespace here
 * since our stub is all no-ops. */
#ifndef STUB_ILU_H
#define STUB_ILU_H

#include "il.h"

#ifdef __cplusplus
extern "C" {
#endif

ILboolean iluInit(void);
ILboolean iluBuildMipmaps(void);
/* Recoil uses ilBuildMipmaps directly (found in il.h on some DevIL versions) */
ILboolean ilBuildMipmaps(void);

#ifdef __cplusplus
}
#endif
#endif
