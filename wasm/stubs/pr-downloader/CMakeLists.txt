# Stub pr-downloader + sibling libs for Emscripten headless Recoil build.
# Provides: pr-downloader, prd::jsoncpp, prd::base64 targets.
# All download operations return failure/empty; replay playback doesn't use them.
cmake_minimum_required(VERSION 3.19)
project(pr_downloader_stub CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The real pr-downloader header includes <Downloader/DownloadEnum.h> relatively,
# so we need that on the include path. We expose the real source tree's src/
# dir as the include root. The stub.cpp compiles against real headers.
set(PRD_REAL_SRC "${CMAKE_SOURCE_DIR}/tools/pr-downloader/src")

# pr-downloader main target — stub implementation
add_library(pr-downloader STATIC pr_downloader_stub.cpp)
target_include_directories(pr-downloader PUBLIC "${PRD_REAL_SRC}")

# jsoncpp: use the real integrated one from pr-downloader submodule
add_subdirectory("${PRD_REAL_SRC}/lib/jsoncpp" "${CMAKE_BINARY_DIR}/prd_jsoncpp")
add_library(prd::jsoncpp ALIAS pr-jsoncpp)

# base64: use the real integrated one
add_subdirectory("${PRD_REAL_SRC}/lib/base64" "${CMAKE_BINARY_DIR}/prd_base64")
add_library(prd::base64 ALIAS pr-base64)

# 7zip: also vendored in pr-downloader; Recoil's SevenZipArchive.cpp includes 7z.h
add_subdirectory("${PRD_REAL_SRC}/lib/7z" "${CMAKE_BINARY_DIR}/prd_7z")
# Expose 7z headers on the global include path so engine code can `#include <7z.h>`
include_directories(BEFORE "${PRD_REAL_SRC}/lib/7z")
