// Stub pr-downloader for Emscripten WASM headless Recoil build.
// Implements the pr-downloader.h public API as no-ops/failures.
// Replay playback never triggers downloads, so this surface is safe.
#include "../../../repos/RecoilEngine/tools/pr-downloader/src/pr-downloader.h"

int  DownloadStart()                                                      { return 0; }
int  DownloadAddByUrl(DownloadEnum::Category, const char*, const char*)   { return -1; }
bool DownloadAdd(unsigned int)                                            { return false; }
int  DownloadSearch(DownloadEnum::Category, const char*)                  { return 0; }
int  DownloadSearch(std::vector<DownloadSearchItem>&)                     { return 0; }
bool DownloadGetInfo(int, downloadInfo&)                                  { return false; }
void DownloadInit()                                                       {}
void DownloadShutdown()                                                   {}
bool DownloadSetConfig(CONFIG, const void*)                               { return true; }
bool DownloadGetConfig(CONFIG, const void**)                              { return false; }
bool DownloadRapidValidate(bool)                                          { return false; }
bool DownloadDumpSDP(const char*)                                         { return false; }
bool ValidateSDP(const char*)                                             { return false; }
void DownloadDisableLogging(bool)                                         {}
void SetDownloadListener(IDownloaderProcessUpdateListener)                {}
char* CalcHash(const char*, int, int)                                     { return nullptr; }
void SetAbortDownloads(bool)                                              {}
DownloadEnum::Category getPlatformEngineCat()                             { return DownloadEnum::CAT_ENGINE_LINUX64; }

// DownloadEnum helpers (defined in pr-downloader normally)
namespace DownloadEnum {
    std::string getCat(Category)                { return ""; }
    Category    getCatFromStr(const std::string&) { return CAT_NONE; }
}
