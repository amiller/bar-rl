# Freetype shim:
#   - Emscripten: use the -sUSE_FREETYPE=1 port (no real Freetype needed).
#   - Native (BAR_USE_STUBS=1): defer to CMake's stock FindFreetype.cmake.
#     The naive `find_package(Freetype)` below would re-find ourselves and
#     infinite-loop, so include the standard module by explicit path.
if (NOT EMSCRIPTEN)
    include("${CMAKE_ROOT}/Modules/FindFreetype.cmake")
    return()
endif()

set(FREETYPE_FOUND TRUE)
set(Freetype_FOUND TRUE)
set(FREETYPE_VERSION_STRING "2.13.2")
set(FREETYPE_LIBRARY "")
set(FREETYPE_LIBRARIES "")
set(FREETYPE_INCLUDE_DIR "")
set(FREETYPE_INCLUDE_DIRS "")

if (NOT TARGET Freetype::Freetype)
    add_library(Freetype::Freetype INTERFACE IMPORTED GLOBAL)
    target_compile_options(Freetype::Freetype INTERFACE "SHELL:-sUSE_FREETYPE=1")
    target_link_options(Freetype::Freetype INTERFACE "SHELL:-sUSE_FREETYPE=1")
endif()
