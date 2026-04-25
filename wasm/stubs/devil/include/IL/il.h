/* Minimal DevIL stub header for Recoil/BAR headless WASM build.
 * Makes Recoil's Bitmap.cpp link; all ops are no-ops. In headless
 * replay mode we never render pixels, so every loaded image is a 1x1
 * RGBA dummy. Sim-side state is unaffected.
 */
#ifndef STUB_IL_H
#define STUB_IL_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stddef.h>

typedef unsigned int    ILenum;
typedef unsigned char   ILboolean;
typedef unsigned int    ILuint;
typedef int             ILint;
typedef int             ILsizei;
typedef unsigned char   ILubyte;
typedef unsigned short  ILushort;
typedef unsigned int    ILbitfield;
typedef float           ILfloat;
typedef double          ILdouble;
typedef char            ILbyte;
typedef short           ILshort;
typedef void*           ILHANDLE;
typedef char            ILchar;   /* real DevIL defines this too */
typedef const char      ILconst_string_elem;
typedef ILchar*         ILstring;
typedef const ILchar*   ILconst_string;

#define IL_FALSE 0
#define IL_TRUE  1

/* Error / query */
#define IL_NO_ERROR           0x0000
#define IL_IMAGE_WIDTH        0x0DE4
#define IL_IMAGE_HEIGHT       0x0DE5
#define IL_IMAGE_BYTES_PER_PIXEL 0x0DE8
#define IL_IMAGE_FORMAT       0x0DEE
#define IL_IMAGE_TYPE         0x0DEF
#define IL_PALETTE_TYPE       0x0636
#define IL_VERSION            0x0DE2
#define IL_ORIGIN_SET         0x0600
#define IL_ORIGIN_UPPER_LEFT  0x0601
#define IL_ORIGIN_LOWER_LEFT  0x0602
#define IL_COMPRESSION_HINT   0x0613
#define IL_NO_COMPRESSION     0x0710
#define IL_JPG_QUALITY        0x0651
#define IL_UNICODE            0x0612
#define IL_DETAILED_TRACY_ZONE 0x1000 /* not real but referenced in Recoil */

/* Pixel formats */
#define IL_COLOUR_INDEX 0x1900
#define IL_ALPHA        0x1906
#define IL_RGB          0x1907
#define IL_RGBA         0x1908
#define IL_BGR          0x80E0
#define IL_BGRA         0x80E1
#define IL_LUMINANCE    0x1909
#define IL_LUMINANCE_ALPHA 0x190A

/* Types */
#define IL_UNSIGNED_BYTE  0x1401
#define IL_UNSIGNED_SHORT 0x1403
#define IL_FLOAT          0x1406
#define IL_TYPE_UNKNOWN   0x0000

/* Palettes */
#define IL_PAL_RGB24   0x0F00
#define IL_PAL_RGB32   0x0F01
#define IL_PAL_RGBA32  0x0F02
#define IL_PAL_BGR24   0x0F03
#define IL_PAL_BGR32   0x0F04
#define IL_PAL_BGRA32  0x0F05

/* File types */
#define IL_RAW  0x0F1A
#define IL_BMP  0x0420
#define IL_JPG  0x0425
#define IL_PNG  0x042A
#define IL_TGA  0x042D
#define IL_TIF  0x042E
#define IL_DDS  0x0437
#define IL_PNM  0x0427
#define IL_HDR  0x0443
#define IL_EXR  0x0442

/* Core API — all are stubs. See il_stub.c */
ILboolean ilInit(void);
void      ilShutDown(void);
ILboolean ilEnable(ILenum mode);
ILboolean ilDisable(ILenum mode);
ILboolean ilHint(ILenum target, ILenum mode);
ILboolean ilOriginFunc(ILenum mode);
ILboolean ilSetInteger(ILenum mode, ILint param);
ILint     ilGetInteger(ILenum mode);
ILenum    ilGetError(void);

void      ilGenImages(ILsizei num, ILuint *images);
void      ilDeleteImages(ILsizei num, const ILuint *images);
void      ilBindImage(ILuint image);

ILboolean ilLoadL(ILenum type, const void *lump, ILuint size);
ILuint    ilSaveL(ILenum type, void *lump, ILuint size);
ILboolean ilSave(ILenum type, const ILchar* filename);
ILboolean ilTexImage(ILuint w, ILuint h, ILuint depth, ILubyte bpp,
                     ILenum format, ILenum type, void *data);
ILubyte*  ilGetData(void);
ILboolean ilCopyPixels(ILuint xoff, ILuint yoff, ILuint zoff,
                       ILuint w,  ILuint h,  ILuint d,
                       ILenum format, ILenum type, void *data);
ILboolean ilConvertImage(ILenum destFormat, ILenum destType);

#ifdef __cplusplus
}
#endif
#endif
