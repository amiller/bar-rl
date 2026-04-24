/* DevIL stub for headless WASM Recoil build. All loads become 1x1 RGBA
 * transparent pixels. Sim never reads these back meaningfully in
 * replay-playback mode. */
#include <IL/il.h>
#include <IL/ilu.h>
#include <string.h>
#include <stdlib.h>

/* Single fake image slot — ilBindImage always selects the same data. */
static ILubyte g_pixels[4] = { 0, 0, 0, 0 };
static ILint   g_width  = 1;
static ILint   g_height = 1;
static ILint   g_bpp    = 4;
static ILint   g_format = IL_RGBA;
static ILint   g_type   = IL_UNSIGNED_BYTE;
static ILuint  g_next_id = 1;

ILboolean ilInit(void)                                { return IL_TRUE; }
void      ilShutDown(void)                            {}
ILboolean ilEnable(ILenum m)                          { (void)m; return IL_TRUE; }
ILboolean ilDisable(ILenum m)                         { (void)m; return IL_TRUE; }
ILboolean ilHint(ILenum t, ILenum m)                  { (void)t; (void)m; return IL_TRUE; }
ILboolean ilOriginFunc(ILenum m)                      { (void)m; return IL_TRUE; }
ILboolean ilSetInteger(ILenum m, ILint v)             { (void)m; (void)v; return IL_TRUE; }
ILenum    ilGetError(void)                            { return IL_NO_ERROR; }

ILint ilGetInteger(ILenum mode) {
    switch (mode) {
        case IL_IMAGE_WIDTH:           return g_width;
        case IL_IMAGE_HEIGHT:          return g_height;
        case IL_IMAGE_BYTES_PER_PIXEL: return g_bpp;
        case IL_IMAGE_FORMAT:          return g_format;
        case IL_IMAGE_TYPE:            return g_type;
        case IL_VERSION:               return 180;
        default:                       return 0;
    }
}

void ilGenImages(ILsizei n, ILuint *images) {
    for (ILsizei i = 0; i < n; ++i) images[i] = g_next_id++;
}
void ilDeleteImages(ILsizei n, const ILuint *images) { (void)n; (void)images; }
void ilBindImage(ILuint image)                       { (void)image; }

/* Any load "succeeds" and produces a 1x1 RGBA zero pixel. */
ILboolean ilLoadL(ILenum type, const void *lump, ILuint size) {
    (void)type; (void)lump; (void)size;
    g_width = 1; g_height = 1; g_bpp = 4;
    g_format = IL_RGBA; g_type = IL_UNSIGNED_BYTE;
    memset(g_pixels, 0, sizeof(g_pixels));
    return IL_TRUE;
}
/* Save reports success with zero bytes written. */
ILuint ilSaveL(ILenum type, void *lump, ILuint size) {
    (void)type; (void)lump; (void)size;
    return 0;
}
ILboolean ilTexImage(ILuint w, ILuint h, ILuint d, ILubyte bpp,
                     ILenum format, ILenum type, void *data) {
    (void)d; (void)data;
    g_width = (ILint)w; g_height = (ILint)h; g_bpp = bpp;
    g_format = format; g_type = type;
    return IL_TRUE;
}
ILubyte* ilGetData(void) { return g_pixels; }

ILboolean ilCopyPixels(ILuint xoff, ILuint yoff, ILuint zoff,
                       ILuint w,  ILuint h,  ILuint d,
                       ILenum format, ILenum type, void *data) {
    (void)xoff; (void)yoff; (void)zoff; (void)d; (void)format; (void)type;
    /* Zero-fill the caller's buffer sized w*h*4 (assume RGBA). */
    if (data) memset(data, 0, (size_t)w * (size_t)h * 4);
    return IL_TRUE;
}
ILboolean ilConvertImage(ILenum destFormat, ILenum destType) {
    g_format = destFormat; g_type = destType; return IL_TRUE;
}

/* ilu */
ILboolean iluInit(void)         { return IL_TRUE; }
ILboolean iluBuildMipmaps(void) { return IL_TRUE; }
ILboolean ilBuildMipmaps(void)  { return IL_TRUE; }
